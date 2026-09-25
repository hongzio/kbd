import Carbon
import Foundation

/// Whether kbd is the system's selected input source (vs. e.g. ABC in a password field).
enum InputSource {
    static var isKbdSelected: Bool {
        let source = TISCopyCurrentKeyboardInputSource().takeRetainedValue()
        guard let raw = TISGetInputSourceProperty(source, kTISPropertyBundleID) else { return false }
        let bundleID = Unmanaged<CFString>.fromOpaque(raw).takeUnretainedValue() as String
        return bundleID == Bundle.main.bundleIdentifier
    }

    static func observeChanges(_ handler: @escaping () -> Void) {
        let name = Notification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String)
        DistributedNotificationCenter.default().addObserver(forName: name, object: nil, queue: .main) { _ in
            handler()
        }
    }
}
