import KbdCore

/// Validated settings from `~/.config/kbd/config.toml`. Defaults apply when the file or a key is absent.
public struct Config: Equatable, Sendable {
    public var toggle = Toggle()
    public var hangul = Hangul()
    public var escape = Escape()
    public var mode = Mode()
    /// Keyed by bundle ID.
    public var apps: [String: AppPolicy] = [:]
    /// Absent `[[ipc.socket]]` means one socket at the default path with the built-in requests.
    public var ipcSockets = [IPCSocket(path: IPCSocket.expand(IPCSocket.defaultPath))]

    public init() {}

    public struct Toggle: Equatable, Sendable {
        /// The physical key the user presses.
        public var key = ToggleKey(name: "right_command")!
        /// F-key a modifier/CapsLock `key` is remapped to. Unused when `key` is already an F-key.
        public var remapTo = ToggleKey(name: "f20")!

        public var needsRemap: Bool { !key.isFunctionKey }
        /// The key code the IME reacts to.
        public var keyCode: UInt16 { (needsRemap ? remapTo : key).keyCode! }
    }

    public struct Hangul: Equatable, Sendable {
        public var layout = "dubeolsik"
        public var backspace = BackspaceUnit.jamo
    }

    public struct Escape: Equatable, Sendable {
        public var enabled = false
        public var keys: [EscapeKey] = [.escape, .controlBracket]
    }

    public enum EscapeKey: String, CaseIterable, Sendable {
        case escape
        case controlBracket = "ctrl+["
    }

    public struct Mode: Equatable, Sendable {
        public var newApp = NewAppMode.inherit
    }

    /// Mode for an app seen for the first time.
    public enum NewAppMode: String, CaseIterable, Sendable {
        case inherit
        case en
        case ko
    }

    public struct AppPolicy: Equatable, Sendable {
        public var onActivate = OnActivate.remember
        /// Overrides `escape.enabled` for this app.
        public var escape: Bool?
        /// How the syllable being composed is shown.
        public var composition = Composition.auto
        /// For apps that drop the key that ended a composition (e.g. Ghostty): when one of these
        /// keys ends it, its text is sent along with the committed syllable and the key is consumed.
        public var commitKeys: [KeyTrigger: String] = [:]

        public init(onActivate: OnActivate = .remember, escape: Bool? = nil,
                    composition: Composition = .auto, commitKeys: [KeyTrigger: String] = [:]) {
            self.onActivate = onActivate
            self.escape = escape
            self.composition = composition
            self.commitKeys = commitKeys
        }
    }

    /// `marked`: the syllable is marked text until committed (works everywhere, but apps see a
    /// composition in progress when e.g. Enter arrives). `inline`: the syllable is real text replaced
    /// on every keystroke, like the system Korean IM in text views. `auto`: probe the client with the
    /// first keystroke and use inline when it can read the text back.
    public enum Composition: String, CaseIterable, Sendable {
        case auto
        case inline
        case marked
    }

    /// A key plus exact modifiers, written as e.g. `enter`, `shift+enter`, `ctrl+tab`.
    public struct KeyTrigger: Hashable, Sendable {
        public enum Key: String, CaseIterable, Sendable {
            case enter  // Return and keypad Enter
            case tab
            case escape
        }

        public struct Modifiers: OptionSet, Hashable, Sendable {
            public let rawValue: Int
            public init(rawValue: Int) { self.rawValue = rawValue }
            public static let shift = Modifiers(rawValue: 1 << 0)
            public static let ctrl = Modifiers(rawValue: 1 << 1)
            public static let alt = Modifiers(rawValue: 1 << 2)
            public static let cmd = Modifiers(rawValue: 1 << 3)

            static let names: [(String, Modifiers)] = [("shift", .shift), ("ctrl", .ctrl), ("alt", .alt), ("cmd", .cmd)]
        }

        public var key: Key
        public var modifiers: Modifiers

        public init(_ key: Key, _ modifiers: Modifiers = []) {
            self.key = key
            self.modifiers = modifiers
        }

        /// Parses `shift+enter`; modifiers in any order, each at most once.
        init?(_ spec: String) {
            var parts = spec.lowercased().split(separator: "+", omittingEmptySubsequences: false).map(String.init)
            guard let keyName = parts.popLast(), let key = Key(rawValue: keyName) else { return nil }
            var modifiers: Modifiers = []
            for part in parts {
                guard let modifier = Modifiers.names.first(where: { $0.0 == part })?.1,
                      !modifiers.contains(modifier) else { return nil }
                modifiers.insert(modifier)
            }
            self.init(key, modifiers)
        }
    }

    public struct Compatibility: Equatable, Sendable {
        public var composition: Composition
        public var commitKeys: [KeyTrigger: String]
    }

    public func compatibility(for bundleID: String?) -> Compatibility {
        let app = bundleID.flatMap { apps[$0] } ?? AppPolicy()
        return Compatibility(composition: app.composition, commitKeys: app.commitKeys)
    }

    public enum OnActivate: String, CaseIterable, Sendable {
        case remember
        case en
        case ko
    }

    public func escapeEnabled(for bundleID: String?) -> Bool {
        bundleID.flatMap { apps[$0]?.escape } ?? escape.enabled
    }
}
