import CoreServices
import Foundation
import KbdConfig

/// Loads `~/.config/kbd/config.toml` and reloads it when it changes. An unusable file keeps the
/// last good config; problems are surfaced in the status menu.
final class ConfigStore {
    static let shared = ConfigStore()

    /// Fixed path: kbd is launched by the system, so shell variables like XDG_CONFIG_HOME aren't visible.
    static let fileURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".config/kbd/config.toml")

    private(set) var config = Config()
    /// Errors (config not applied) and warnings (applied), for display.
    private(set) var problems: [String] = []
    /// The file on disk couldn't be applied (warnings don't count).
    private(set) var hasError = false
    private var loadObservers: [() -> Void] = []
    /// Bumped on every successful load, so per-client state (composers) can rebuild lazily.
    private(set) var generation = 0

    private var observers: [(Config) -> Void] = []
    private var stream: FSEventStreamRef?
    private var watchedPaths: [String] = []

    func observe(_ observer: @escaping (Config) -> Void) {
        observers.append(observer)
    }

    /// Called after every load attempt, successful or not (e.g. to refresh error display, retry sockets).
    func observeLoad(_ observer: @escaping () -> Void) {
        loadObservers.append(observer)
    }

    func load() {
        // Watch first: when the file is missing, its creation is exactly what we wait for.
        defer {
            restartWatchingIfNeeded()
            loadObservers.forEach { $0() }
        }
        let url = Self.fileURL
        guard FileManager.default.fileExists(atPath: url.path) else {
            publish(Config(), problems: [])
            Log.main.notice("config: no file, using defaults")
            return
        }
        do {
            let source = try String(contentsOf: url, encoding: .utf8)
            let parsed = try ConfigParser.parse(source)
            publish(parsed.config, problems: parsed.warnings.map { "⚠︎ \($0)" })
            Log.main.notice("config: loaded (\(parsed.warnings.count) warnings)")
        } catch let error as ConfigError {
            fail(["설정을 적용하지 못했습니다 (이전 설정 유지):"] + error.messages.map { "✗ \($0)" })
            Log.main.error("config: \(error.description, privacy: .public)")
        } catch {
            fail(["설정 파일을 읽지 못했습니다: \(error.localizedDescription)"])
            Log.main.error("config: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Creates the file from the template when missing, so the menu can open something useful.
    func ensureFileExists() throws {
        let url = Self.fileURL
        guard !FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try ConfigTemplate.text.write(to: url, atomically: true, encoding: .utf8)
        load()
    }

    /// Keeps the last good config; on the very first load that means the defaults, which still
    /// have to be published so observers (e.g. the toggle remap) start up.
    private func fail(_ problems: [String]) {
        if generation == 0 {
            publish(Config(), problems: problems)
        } else {
            self.problems = problems
        }
        hasError = true  // after publish, which clears it
    }

    private func publish(_ config: Config, problems: [String]) {
        self.problems = problems
        hasError = false
        guard config != self.config || generation == 0 else { return }
        self.config = config
        generation += 1
        observers.forEach { $0(config) }
    }

    // MARK: - Watching

    /// Directories to watch: the nearest existing ancestor of the config directory (editors save
    /// by rename, and the directory may not exist yet) plus the symlink target's directory
    /// (dotfile managers like stow/chezmoi).
    private func pathsToWatch() -> [String] {
        let fm = FileManager.default
        var dir = Self.fileURL.deletingLastPathComponent()
        while !fm.fileExists(atPath: dir.path), dir.path != "/" {
            dir = dir.deletingLastPathComponent()
        }
        var paths = [dir.path]
        let resolved = Self.fileURL.resolvingSymlinksInPath()
        if resolved != Self.fileURL {
            paths.append(resolved.deletingLastPathComponent().path)
        }
        return paths
    }

    private func restartWatchingIfNeeded() {
        let paths = pathsToWatch()
        guard paths != watchedPaths else { return }
        if let stream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
        }
        watchedPaths = paths

        var context = FSEventStreamContext(
            version: 0, info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil, release: nil, copyDescription: nil)
        let callback: FSEventStreamCallback = { _, info, count, eventPaths, _, _ in
            let store = Unmanaged<ConfigStore>.fromOpaque(info!).takeUnretainedValue()
            let paths = unsafeBitCast(eventPaths, to: NSArray.self) as? [String] ?? []
            if store.isRelevant(paths.prefix(count)) {
                store.load()
            }
        }
        // 0.2s latency doubles as the debounce for editors that write several times per save.
        stream = FSEventStreamCreate(
            nil, callback, &context, paths as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 0.2,
            FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes))
        guard let stream else { return }
        FSEventStreamSetDispatchQueue(stream, .main)
        FSEventStreamStart(stream)
        Log.main.notice("config: watching \(paths.joined(separator: ", "), privacy: .public)")
    }

    private func isRelevant(_ eventPaths: ArraySlice<String>) -> Bool {
        let configDir = Self.fileURL.deletingLastPathComponent().resolvingSymlinksInPath().path
        let target = Self.fileURL.resolvingSymlinksInPath().path
        return eventPaths.contains { path in
            let resolved = URL(fileURLWithPath: path).resolvingSymlinksInPath().path
            return resolved == target || resolved.hasPrefix(configDir)
        }
    }
}
