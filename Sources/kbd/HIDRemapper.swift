import Foundation
import IOKit
import IOKit.hid
import KbdConfig

/// Applies `UserKeyMapping` (same mechanism as `hidutil property --set`) to every keyboard service,
/// merging with mappings owned by other tools, and re-applies when keyboards are attached.
/// The mapping lives in the HID system, not in this process, so it must be removed on exit.
final class HIDRemapper {
    static let shared = HIDRemapper()

    private static let mappingKey = "UserKeyMapping" as CFString
    private static let srcKey = "HIDKeyboardModifierMappingSrc"
    private static let dstKey = "HIDKeyboardModifierMappingDst"

    private var mapping: (src: UInt64, dst: UInt64)?
    private var notifyPort: IONotificationPortRef?
    private var iterator: io_iterator_t = 0

    /// Remaps `source` to `target`, replacing any mapping set earlier; nil removes it.
    func setMapping(from source: ToggleKey?, to target: ToggleKey?) {
        let new = source.flatMap { s in target.map { (s.hidValue, $0.hidValue) } }
        if let old = mapping, let new, old == new { return }
        remove()
        mapping = new
        guard mapping != nil else { return }
        apply()
        observeKeyboardArrivals()
    }

    /// Removes only our entry, leaving other tools' mappings intact.
    func remove() {
        guard let (src, dst) = mapping else { return }
        var removed: [String] = []
        forEachKeyboard { service in
            let mappings = Self.mappings(of: service)
            let kept = mappings.filter {
                !($0[Self.srcKey]?.uint64Value == src && $0[Self.dstKey]?.uint64Value == dst)
            }
            guard kept.count != mappings.count else { return }
            IOHIDServiceClientSetProperty(service, Self.mappingKey, kept as CFArray)
            removed.append(Self.describe(service))
        }
        mapping = nil
        Log.main.notice("HID remap removed from [\(removed.joined(separator: ", "), privacy: .public)]")
    }

    private func apply() {
        guard let (src, dst) = mapping else { return }
        var applied: [String] = []
        forEachKeyboard { service in
            var mappings = Self.mappings(of: service).filter { $0[Self.srcKey]?.uint64Value != src }
            mappings.append([Self.srcKey: NSNumber(value: src), Self.dstKey: NSNumber(value: dst)])
            let ok = IOHIDServiceClientSetProperty(service, Self.mappingKey, mappings as CFArray)
            applied.append(Self.describe(service) + (ok ? "" : " (failed)"))
        }
        Log.main.notice("HID remap applied 0x\(String(src, radix: 16), privacy: .public) -> 0x\(String(dst, radix: 16), privacy: .public) on [\(applied.joined(separator: ", "), privacy: .public)]")
    }

    private func forEachKeyboard(_ body: (IOHIDServiceClient) -> Void) {
        // A client never lists services added after it was created, so a long-lived one misses
        // keyboards that come and go (Karabiner re-creates its virtual keyboard on wake and login).
        let client = IOHIDEventSystemClientCreateSimpleClient(kCFAllocatorDefault)
        guard let services = IOHIDEventSystemClientCopyServices(client) as? [IOHIDServiceClient] else { return }
        for service in services
        where IOHIDServiceClientConformsTo(service, UInt32(kHIDPage_GenericDesktop), UInt32(kHIDUsage_GD_Keyboard)) != 0 {
            body(service)
        }
    }

    private static func mappings(of service: IOHIDServiceClient) -> [[String: NSNumber]] {
        IOHIDServiceClientCopyProperty(service, mappingKey) as? [[String: NSNumber]] ?? []
    }

    /// "Product 0x<registry id>", matching `hidutil list`.
    private static func describe(_ service: IOHIDServiceClient) -> String {
        let product = IOHIDServiceClientCopyProperty(service, kIOHIDProductKey as CFString) as? String ?? "?"
        let id = (IOHIDServiceClientGetRegistryID(service) as? NSNumber)?.uint64Value ?? 0
        return "\(product) 0x\(String(id, radix: 16))"
    }

    private func observeKeyboardArrivals() {
        guard notifyPort == nil else { return }
        notifyPort = IONotificationPortCreate(kIOMainPortDefault)
        guard let notifyPort else { return }
        IONotificationPortSetDispatchQueue(notifyPort, .main)
        let context = Unmanaged.passUnretained(self).toOpaque()
        let callback: IOServiceMatchingCallback = { context, iterator in
            let remapper = Unmanaged<HIDRemapper>.fromOpaque(context!).takeUnretainedValue()
            remapper.drain(iterator)
            // The event-system service shows up slightly after the IOKit service.
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { remapper.apply() }
        }
        IOServiceAddMatchingNotification(
            notifyPort, kIOFirstMatchNotification, IOServiceMatching("IOHIDEventService"),
            callback, context, &iterator)
        drain(iterator)  // arms the notification
    }

    private func drain(_ iterator: io_iterator_t) {
        while case let object = IOIteratorNext(iterator), object != 0 {
            IOObjectRelease(object)
        }
    }
}
