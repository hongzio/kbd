import Carbon
import Foundation

/// The toggle key as a system-wide hot key. The system delivers it to kbd instead of the focused
/// app, so no app ever sees it (Ghostty, for one, forwards keys to the terminal even when the input
/// method handled them). Needs no permission. If registration fails, the input method still
/// toggles on the key through the normal key path.
final class ToggleHotKey {
    static let shared = ToggleHotKey()

    /// Why the hot key isn't registered, for the status menu.
    private(set) var problem: String?
    var onPress: (() -> Void)?

    private var hotKey: EventHotKeyRef?
    private var registeredKeyCode: UInt16?
    private var handlerInstalled = false

    func register(keyCode: UInt16) {
        guard keyCode != registeredKeyCode || hotKey == nil else { return }
        unregister()
        installHandlerIfNeeded()

        let id = EventHotKeyID(signature: OSType(0x6B62_6421), id: 1)  // 'kbd!'
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(UInt32(keyCode), 0, id, GetApplicationEventTarget(), 0, &ref)
        if status == noErr, let ref {
            hotKey = ref
            registeredKeyCode = keyCode
            problem = nil
            Log.main.notice("hotkey: registered keyCode=\(keyCode)")
        } else {
            problem = "⚠︎ 전환 키를 전역 단축키로 등록하지 못했습니다 (다른 앱이 사용 중일 수 있음, status \(status))"
            Log.main.error("hotkey: RegisterEventHotKey keyCode=\(keyCode) failed: \(status)")
        }
    }

    func unregister() {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        hotKey = nil
        registeredKeyCode = nil
    }

    private func installHandlerIfNeeded() {
        guard !handlerInstalled else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let status = InstallEventHandler(GetApplicationEventTarget(), { _, _, userData in
            let hotKey = Unmanaged<ToggleHotKey>.fromOpaque(userData!).takeUnretainedValue()
            hotKey.onPress?()
            return noErr
        }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), nil)
        handlerInstalled = status == noErr
    }
}
