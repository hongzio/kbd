import AppKit
import InputMethodKit
import KbdConfig
import KbdCore

private enum KeyCode {
    static let delete: UInt16 = 51
    static let escape: UInt16 = 53
    static let leftBracket: UInt16 = 33
}

@objc(KbdInputController)
final class InputController: IMKInputController {
    /// The controller of the focused client, so mode changes from outside (IPC) can commit its composition.
    private(set) weak static var active: InputController?

    private var composer = InputController.makeComposer(ConfigStore.shared.config)
    private var composerGeneration = ConfigStore.shared.generation

    override func recognizedEvents(_ sender: Any!) -> Int {
        Int(NSEvent.EventTypeMask.keyDown.rawValue)
    }

    override func activateServer(_ sender: Any!) {
        Self.active = self
        let client = sender as? IMKTextInput
        client?.overrideKeyboard(withKeyboardNamed: "com.apple.keylayout.ABC")
        ModeState.shared.activate(app: client?.bundleIdentifier())
    }

    override func deactivateServer(_ sender: Any!) {
        commit(sender as? IMKTextInput)
        if Self.active === self { Self.active = nil }
    }

    /// Commits whatever is being composed in the focused client.
    static func commitActiveComposition() {
        guard let active else { return }
        active.commit(active.client())
    }

    override func commitComposition(_ sender: Any!) {
        commit(sender as? IMKTextInput)
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
            commit(client)
            composer = Self.makeComposer(config)
            composerGeneration = ConfigStore.shared.generation
        }

        if event.keyCode == config.toggle.keyCode {
            // Dedicated key (remapped at HID level): toggle on press, never forward it.
            if !event.isARepeat {
                commit(client)
                ModeState.shared.set(ModeState.shared.mode.toggled)
            }
            return true
        }

        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if Self.isEscape(event, flags: flags, keys: config.escape.keys),
           config.escapeEnabled(for: client.bundleIdentifier()) {
            // Switch to roman and let the app still receive ESC (vim).
            commit(client)
            ModeState.shared.set(.roman)
            return false
        }

        if !flags.intersection([.command, .control, .option]).isEmpty {
            // Commit and pass through; the ABC override makes the app see ⌘A, not ⌘ㅁ.
            commit(client)
            return false
        }

        guard ModeState.shared.mode == .hangul else { return false }

        let wasComposing = !composer.isEmpty
        if event.keyCode == KeyCode.delete {
            guard let result = composer.backspace() else { return false }
            apply(result, client, wasComposing: wasComposing)
            return true
        }

        guard let key = Self.layoutKey(event, shift: flags.contains(.shift)) else {
            // Arrows, function keys, etc.: commit then let the app handle the key.
            commit(client)
            return false
        }
        let result = composer.process(key)
        apply(result, client, wasComposing: wasComposing)
        return result.handled
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

    private func apply(_ result: EngineResult, _ client: IMKTextInput, wasComposing: Bool) {
        if !result.commit.isEmpty {
            client.insertText(result.commit, replacementRange: NSRange(location: NSNotFound, length: 0))
        }
        // insertText replaces the marked text, so clearing is only needed when composition ended
        // without a commit (backspace to empty). Never send empty marked text otherwise.
        if !result.preedit.isEmpty || (wasComposing && result.commit.isEmpty) {
            client.setMarkedText(
                result.preedit,
                selectionRange: NSRange(location: (result.preedit as NSString).length, length: 0),
                replacementRange: NSRange(location: NSNotFound, length: 0)
            )
        }
    }

    private func commit(_ client: IMKTextInput?) {
        guard !composer.isEmpty else { return }
        let text = composer.flush()
        client?.insertText(text, replacementRange: NSRange(location: NSNotFound, length: 0))
    }
}
