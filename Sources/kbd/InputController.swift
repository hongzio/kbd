import AppKit
import InputMethodKit
import KbdConfig
import KbdCore

private enum KeyCode {
    static let delete: UInt16 = 51
    static let escape: UInt16 = 53
    static let leftBracket: UInt16 = 33
    static let `return`: UInt16 = 36
    static let keypadEnter: UInt16 = 76
    static let tab: UInt16 = 48
}

private let noReplacement = NSRange(location: NSNotFound, length: 0)

/// The syllable being composed when it lives in the document as real text (inline composition).
private struct InlineSyllable {
    var location: Int
    var text: String
    var range: NSRange { NSRange(location: location, length: (text as NSString).length) }
}

@objc(KbdInputController)
final class InputController: IMKInputController {
    /// The controller of the focused client, so mode changes from outside (IPC) can commit its composition.
    private(set) weak static var active: InputController?

    private var composer = InputController.makeComposer(ConfigStore.shared.config)
    private var composerGeneration = ConfigStore.shared.generation

    /// Set while composing inline; nil when composing as marked text (or not composing).
    private var inline: InlineSyllable?
    /// `composition = auto`: whether this client proved it can read back and replace text.
    /// nil until probed with a keystroke.
    private var inlineSupported: Bool?

    override func recognizedEvents(_ sender: Any!) -> Int {
        Int(NSEvent.EventTypeMask.keyDown.rawValue)
    }

    override func activateServer(_ sender: Any!) {
        Self.active = self
        inline = nil
        inlineSupported = nil
        let client = sender as? IMKTextInput
        client?.overrideKeyboard(withKeyboardNamed: "com.apple.keylayout.ABC")
        ModeState.shared.activate(app: client?.bundleIdentifier())
    }

    override func deactivateServer(_ sender: Any!) {
        finishOutsideKeyEvent(sender as? IMKTextInput)
        if Self.active === self { Self.active = nil }
    }

    override func commitComposition(_ sender: Any!) {
        finishOutsideKeyEvent(sender as? IMKTextInput)
    }

    /// Commits whatever is being composed in the focused client (toggle hot key, IPC).
    static func commitActiveComposition() {
        guard let active else { return }
        active.finishOutsideKeyEvent(active.client())
    }

    override func handle(_ event: NSEvent!, client sender: Any!) -> Bool {
        guard let event, event.type == .keyDown, let client = sender as? IMKTextInput else { return false }
        return handleKeyDown(event, client: client)
    }

    // MARK: - Key handling

    private func handleKeyDown(_ event: NSEvent, client: IMKTextInput) -> Bool {
        let config = ConfigStore.shared.config
        if composerGeneration != ConfigStore.shared.generation {
            // Layout or backspace unit may have changed.
            finishComposition(client)
            composer = Self.makeComposer(config)
            composerGeneration = ConfigStore.shared.generation
        }
        if inline != nil, !inlineIsIntact(client) {
            // The caret moved or the text changed (click, app edit): the syllable is already real
            // text, so just stop composing it.
            abandonInline()
        }

        if event.keyCode == config.toggle.keyCode {
            // Only reached when the toggle hot key couldn't be registered: dedicated key
            // (remapped at HID level), toggle on press, never forward it.
            if !event.isARepeat {
                finishComposition(client, endingKey: event)
                ModeState.shared.set(ModeState.shared.mode.toggled)
            }
            return true
        }

        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if Self.isEscape(event, flags: flags, keys: config.escape.keys),
           config.escapeEnabled(for: client.bundleIdentifier()) {
            // Switch to roman and let the app still receive ESC (vim).
            let consumed = finishComposition(client, endingKey: event)
            ModeState.shared.set(.roman)
            return consumed
        }

        if !flags.intersection([.command, .control, .option]).isEmpty {
            // The ABC override makes the app see ⌘A, not ⌘ㅁ.
            return finishComposition(client, endingKey: event)
        }

        guard ModeState.shared.mode == .hangul else { return false }

        if event.keyCode == KeyCode.delete {
            guard let result = composer.backspace() else { return false }
            show(result, client)
            return true
        }

        guard let key = Self.layoutKey(event, shift: flags.contains(.shift)) else {
            // Arrows, function keys, etc.
            return finishComposition(client, endingKey: event)
        }
        let result = composer.process(key)
        guard result.handled else {
            // Not a layout key (space, digits, Enter...): the engine flushed the syllable.
            return deliver(result.commit, client, endingKey: event)
        }
        show(result, client)
        return true
    }

    private static func isEscape(_ event: NSEvent, flags: NSEvent.ModifierFlags, keys: [Config.EscapeKey]) -> Bool {
        keys.contains { key in
            switch key {
            case .escape:
                event.keyCode == KeyCode.escape
            case .controlBracket:
                event.keyCode == KeyCode.leftBracket && flags.intersection([.command, .control, .option]) == .control
            }
        }
    }

    /// ABC-layout character for the engine. Letter case follows Shift only, so CapsLock
    /// doesn't turn ㄱ into ㄲ.
    private static func layoutKey(_ event: NSEvent, shift: Bool) -> Character? {
        guard let char = event.charactersIgnoringModifiers?.first, char.isASCII else { return nil }
        guard char.isLetter else { return char }
        return Character(shift ? char.uppercased() : char.lowercased())
    }

    private static func makeComposer(_ config: Config) -> HangulComposer {
        let layout = Layout.builtIn(config.hangul.layout) ?? .dubeolsik
        return try! HangulComposer(layout: layout, backspaceUnit: config.hangul.backspace)
    }

    private func compatibility(_ client: IMKTextInput) -> Config.Compatibility {
        ConfigStore.shared.config.compatibility(for: client.bundleIdentifier())
    }

    // MARK: - Showing the composition

    private func show(_ result: EngineResult, _ client: IMKTextInput) {
        switch compatibility(client).composition {
        case .marked:
            showMarked(result, client)
        case .inline:
            showInline(result, client)
        case .auto:
            switch inlineSupported {
            case true?:
                showInline(result, client)
            case false?:
                showMarked(result, client)
            case nil:
                showMarked(result, client)
                probeInline(client)
            }
        }
    }

    private func showMarked(_ result: EngineResult, _ client: IMKTextInput) {
        if !result.commit.isEmpty {
            client.insertText(result.commit, replacementRange: noReplacement)
        }
        // insertText replaces the marked text, so only send marked text when there is some to
        // show, or to clear it when composition ended without a commit (backspace to empty).
        if !result.preedit.isEmpty || result.commit.isEmpty {
            client.setMarkedText(
                result.preedit,
                selectionRange: NSRange(location: (result.preedit as NSString).length, length: 0),
                replacementRange: noReplacement
            )
        }
    }

    /// The syllable is real text that is replaced on every keystroke, so apps never see a
    /// composition in progress (what the system Korean IM does in text views).
    private func showInline(_ result: EngineResult, _ client: IMKTextInput) {
        let location: Int
        let replacing: NSRange
        if let inline {
            location = inline.location
            replacing = inline.range
        } else {
            let selection = client.selectedRange()
            guard selection.location != NSNotFound else {
                inlineSupported = false
                return showMarked(result, client)
            }
            location = selection.location
            replacing = noReplacement  // insert at the caret, replacing any selection
        }
        client.insertText(result.commit + result.preedit, replacementRange: replacing)

        guard !result.preedit.isEmpty else {
            inline = nil
            return
        }
        inline = InlineSyllable(location: location + (result.commit as NSString).length, text: result.preedit)
        if !inlineIsIntact(client) {
            // The client didn't apply the edit where we expected; don't risk replacing its text.
            Log.main.notice("inline: client didn't keep the syllable, falling back to marked text")
            inlineSupported = false
            abandonInline()
        }
    }

    /// With the syllable just shown as marked text, checks that the client reports its range and
    /// reads it back; if so, turns it into inline text right away. Terminals fail this (Ghostty
    /// returns the mouse selection for any range), so they stay on marked text.
    private func probeInline(_ client: IMKTextInput) {
        let preedit = composer.preedit
        guard !preedit.isEmpty else { return }
        let marked = client.markedRange()
        let supported = marked.location != NSNotFound
            && marked.length == (preedit as NSString).length
            && client.attributedSubstring(from: marked)?.string == preedit
        inlineSupported = supported
        Log.main.notice("inline: probe app=\(client.bundleIdentifier() ?? "?", privacy: .public) supported=\(supported)")
        guard supported else { return }

        client.insertText(preedit, replacementRange: marked)
        inline = InlineSyllable(location: marked.location, text: preedit)
        if !inlineIsIntact(client) {
            inlineSupported = false
            abandonInline()
        }
    }

    /// The caret is right after the inline syllable and the document still contains it.
    private func inlineIsIntact(_ client: IMKTextInput) -> Bool {
        guard let inline else { return true }
        let selection = client.selectedRange()
        guard selection.location == NSMaxRange(inline.range), selection.length == 0 else { return false }
        return client.attributedSubstring(from: inline.range)?.string == inline.text
    }

    /// Stops composing an inline syllable; its text stays in the document as typed.
    private func abandonInline() {
        inline = nil
        _ = composer.flush()
    }

    // MARK: - Ending the composition

    /// Commits the composition from outside a key event (focus change, hot key, IPC).
    /// Don't verify via markedRange() afterwards: the client may answer it before applying the
    /// insert, which looks like the insert was ignored.
    private func finishOutsideKeyEvent(_ client: IMKTextInput?) {
        finishComposition(client)
    }

    /// Commits the composition, e.g. because `endingKey` isn't part of it.
    /// Returns whether that key must be consumed instead of reaching the app.
    @discardableResult
    private func finishComposition(_ client: IMKTextInput?, endingKey event: NSEvent? = nil) -> Bool {
        guard !composer.isEmpty else {
            inline = nil
            return false
        }
        return deliver(composer.flush(), client, endingKey: event)
    }

    /// Commits `text`, the composition just flushed from the engine.
    private func deliver(_ text: String, _ client: IMKTextInput?, endingKey event: NSEvent?) -> Bool {
        if inline != nil {
            // Already real text in the document.
            inline = nil
            return false
        }
        guard let client, !text.isEmpty else { return false }

        // Apps like Ghostty drop the key that ended a composition: send the text configured for
        // that key along with the committed syllable, in this same key event.
        if let event, let trigger = Self.trigger(event),
           let keyText = compatibility(client).commitKeys[trigger] {
            client.insertText(text + keyText, replacementRange: noReplacement)
            return true
        }
        client.insertText(text, replacementRange: noReplacement)
        return false
    }

    /// The event as a `commit_keys` trigger, if it is one of the keys that can be configured.
    private static func trigger(_ event: NSEvent) -> Config.KeyTrigger? {
        let key: Config.KeyTrigger.Key
        switch event.keyCode {
        case KeyCode.return, KeyCode.keypadEnter: key = .enter
        case KeyCode.tab: key = .tab
        case KeyCode.escape: key = .escape
        default: return nil
        }
        let flags = event.modifierFlags
        var modifiers: Config.KeyTrigger.Modifiers = []
        if flags.contains(.shift) { modifiers.insert(.shift) }
        if flags.contains(.control) { modifiers.insert(.ctrl) }
        if flags.contains(.option) { modifiers.insert(.alt) }
        if flags.contains(.command) { modifiers.insert(.cmd) }
        return Config.KeyTrigger(key, modifiers)
    }
}
