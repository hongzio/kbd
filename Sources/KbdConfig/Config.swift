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
