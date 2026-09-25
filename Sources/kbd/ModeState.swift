import Foundation
import KbdConfig

enum InputMode: String {
    case hangul
    case roman

    var toggled: InputMode { self == .hangul ? .roman : .hangul }
    /// Name used in config and IPC.
    var shortName: String { self == .hangul ? "ko" : "en" }
}

/// Current mode, remembered per app (bundle ID). Lives only in kbd: the system always sees a
/// single kbd input mode, and the menu bar shows kbd's own status item.
final class ModeState {
    static let shared = ModeState()

    private(set) var mode: InputMode = .roman
    private(set) var currentApp: String?
    private var modeByApp: [String: InputMode] = [:]
    private var observers: [() -> Void] = []

    /// Called when the mode or the focused app changes.
    func observe(_ observer: @escaping () -> Void) {
        observers.append(observer)
    }

    /// Toggle key, escape, IPC. Returns false if already in `newMode`.
    @discardableResult
    func set(_ newMode: InputMode) -> Bool {
        guard newMode != mode else { return false }
        mode = newMode
        remember()
        notify()
        return true
    }

    /// A client became active: apply the app's policy (fixed start mode, or its remembered mode).
    func activate(app: String?) {
        guard let app, app != currentApp else { return }
        currentApp = app
        let config = ConfigStore.shared.config
        let restored: InputMode = switch config.apps[app]?.onActivate ?? .remember {
        case .en: .roman
        case .ko: .hangul
        case .remember: modeByApp[app] ?? newAppMode(config.mode.newApp)
        }
        Log.main.notice("activate app=\(app, privacy: .public) mode=\(restored.rawValue, privacy: .public)")
        mode = restored
        remember()
        notify()
    }

    private func newAppMode(_ policy: Config.NewAppMode) -> InputMode {
        switch policy {
        case .inherit: mode
        case .en: .roman
        case .ko: .hangul
        }
    }

    private func remember() {
        if let currentApp { modeByApp[currentApp] = mode }
    }

    private func notify() {
        observers.forEach { $0() }
    }
}
