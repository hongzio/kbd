import AppKit

/// kbd's own menu bar indicator, redrawn synchronously on mode change. Dimmed while another input
/// source (e.g. ABC in a password field) is selected. Its menu shows config problems.
final class StatusIcon: NSObject, NSMenuDelegate {
    static let shared = StatusIcon()

    private var item: NSStatusItem?

    func install() {
        // Fixed width so "한" / "A" don't shift neighbouring items.
        let item = NSStatusBar.system.statusItem(withLength: 24)
        item.button?.font = .systemFont(ofSize: 13, weight: .semibold)
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        self.item = item
        update()
        refreshSelectedState()
        ModeState.shared.observe { [weak self] in self?.update() }
        ConfigStore.shared.observeLoad { [weak self] in self?.update() }
        InputSource.observeChanges { [weak self] in self?.refreshSelectedState() }
    }

    private func update() {
        let mode = ModeState.shared.mode
        // "!" while the config file has errors; details are in the menu.
        let badge = ConfigStore.shared.hasError ? "!" : ""
        item?.button?.title = (mode == .hangul ? "한" : "A") + badge
    }

    private func refreshSelectedState() {
        item?.button?.appearsDisabled = !InputSource.isKbdSelected
    }

    // MARK: - Menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let mode = ModeState.shared.mode == .hangul ? "한글" : "영문"
        menu.addItem(NSMenuItem(title: "kbd — \(mode)", action: nil, keyEquivalent: ""))

        let problems = ConfigStore.shared.problems + IPCServer.shared.problems
            + [ToggleHotKey.shared.problem].compactMap { $0 }
        if !problems.isEmpty {
            menu.addItem(.separator())
            for problem in problems {
                menu.addItem(NSMenuItem(title: problem, action: nil, keyEquivalent: ""))
            }
        }

        menu.addItem(.separator())
        let open = NSMenuItem(title: "설정 파일 열기", action: #selector(openConfig), keyEquivalent: "")
        open.target = self
        menu.addItem(open)
        let reload = NSMenuItem(title: "설정 다시 읽기", action: #selector(reloadConfig), keyEquivalent: "")
        reload.target = self
        menu.addItem(reload)
    }

    @objc private func openConfig() {
        do {
            try ConfigStore.shared.ensureFileExists()
        } catch {
            Log.main.error("config: can't create file: \(error.localizedDescription, privacy: .public)")
            return
        }
        let url = ConfigStore.fileURL
        // .toml often has no default app; fall back to TextEdit.
        if !NSWorkspace.shared.open(url),
           let textEdit = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.TextEdit") {
            NSWorkspace.shared.open([url], withApplicationAt: textEdit, configuration: NSWorkspace.OpenConfiguration())
        }
    }

    @objc private func reloadConfig() {
        ConfigStore.shared.load()
    }
}
