/// A physical key that can be dedicated to mode toggling.
/// Modifiers and CapsLock are remapped at the HID level to an F-key so they lose their original
/// function; F-keys are used as-is (e.g. already remapped by Karabiner).
public struct ToggleKey: Equatable, Sendable {
    public let name: String
    /// HID keyboard page (0x07) usage.
    public let usage: UInt32

    static let named: [(String, UInt32)] = [
        ("caps_lock", 0x39),
        ("left_control", 0xE0), ("left_shift", 0xE1), ("left_option", 0xE2), ("left_command", 0xE3),
        ("right_control", 0xE4), ("right_shift", 0xE5), ("right_option", 0xE6), ("right_command", 0xE7),
        ("f13", 0x68), ("f14", 0x69), ("f15", 0x6A), ("f16", 0x6B),
        ("f17", 0x6C), ("f18", 0x6D), ("f19", 0x6E), ("f20", 0x6F),
    ]

    /// macOS virtual key codes for F13–F20 (not contiguous).
    private static let functionKeyCodes: [UInt32: UInt16] = [
        0x68: 105, 0x69: 107, 0x6A: 113, 0x6B: 106, 0x6C: 64, 0x6D: 79, 0x6E: 80, 0x6F: 90,
    ]

    static var allNames: [String] { named.map(\.0) }
    static var functionKeyNames: [String] { named.filter { functionKeyCodes[$0.1] != nil }.map(\.0) }

    public init?(name: String) {
        guard let usage = Self.named.first(where: { $0.0 == name })?.1 else { return nil }
        self.name = name
        self.usage = usage
    }

    public var isFunctionKey: Bool { Self.functionKeyCodes[usage] != nil }

    /// Virtual key code the IME will see, if this is an F-key.
    public var keyCode: UInt16? { Self.functionKeyCodes[usage] }

    /// Value used in `UserKeyMapping` (page << 32 | usage).
    public var hidValue: UInt64 { 0x7_0000_0000 | UInt64(usage) }
}
