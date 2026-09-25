import Darwin
import Foundation
import KbdConfig

/// Unix-socket listeners from `[[ipc.socket]]`. Line protocol: one request line, one reply line,
/// then close — except `subscribe`, which stays open and gets a line per change.
/// Everything runs on the main queue: traffic is tiny, sockets are non-blocking, and mode state
/// is main-thread owned.
final class IPCServer {
    static let shared = IPCServer()

    /// Sockets that couldn't be opened, for the status menu.
    private(set) var problems: [String] = []
    private var listeners: [String: Listener] = [:]

    /// Opens new sockets, closes removed ones, updates request tables. Idempotent, so it also
    /// retries sockets that failed earlier (e.g. the path was held by another process).
    func apply(_ sockets: [IPCSocket]) {
        problems = []
        let wanted = Set(sockets.map(\.path))
        for (path, listener) in listeners where !wanted.contains(path) {
            listener.close()
            listeners[path] = nil
        }
        for socket in sockets {
            if let existing = listeners[socket.path] {
                existing.requests = socket.requests
                continue
            }
            do {
                listeners[socket.path] = try Listener(socket)
                Log.main.notice("ipc: listening on \(socket.path, privacy: .public)")
            } catch {
                problems.append("⚠︎ 소켓을 열지 못했습니다 \(socket.path): \(error.message)")
                Log.main.error("ipc: \(socket.path, privacy: .public): \(error.message, privacy: .public)")
            }
        }
    }

    func closeAll() {
        listeners.values.forEach { $0.close() }
        listeners = [:]
    }

    /// Pushes the current state to every subscriber.
    func broadcast() {
        listeners.values.forEach { $0.broadcast() }
    }
}

// MARK: - Actions

private enum IPCActions {
    static let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"

    /// Runs the action and returns the values for reply templates.
    static func perform(_ action: IPCAction) -> [String: String] {
        var result = ""
        switch action {
        case .ping, .version, .get, .subscribe:
            break
        case .set(let target):
            result = switchMode(to: target == .en ? .roman : .hangul) ? "switched" : "noop"
        case .toggle:
            result = switchMode(to: ModeState.shared.mode.toggled) ? "switched" : "noop"
        }
        return values(result: result)
    }

    static func values(result: String = "") -> [String: String] {
        [
            "mode": ModeState.shared.mode.shortName,
            "app": ModeState.shared.currentApp ?? "-",
            "result": result,
            "active": InputSource.isKbdSelected ? "active" : "inactive",
            "version": version,
        ]
    }

    /// Same as pressing the toggle key: commit the focused client's composition, then switch.
    private static func switchMode(to mode: InputMode) -> Bool {
        guard mode != ModeState.shared.mode else { return false }
        InputController.commitActiveComposition()
        return ModeState.shared.set(mode)
    }
}

// MARK: - Listener

private struct ListenerError: Error {
    let message: String
}

private final class Listener {
    static let maxConnections = 16
    static let maxLineBytes = 4096
    static let readTimeout: TimeInterval = 2

    let path: String
    var requests: [String: IPCRequest]
    private let fd: Int32
    private let acceptSource: DispatchSourceRead
    private var connections: [ObjectIdentifier: Connection] = [:]

    init(_ socket: IPCSocket) throws(ListenerError) {
        path = socket.path
        requests = socket.requests
        try Self.prepare(path)

        let fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw ListenerError(message: "socket(): \(String(cString: strerror(errno)))") }
        let bound = Self.withAddress(path) { address, length in
            let oldMask = umask(0o177)  // socket file 0600
            defer { umask(oldMask) }
            return bind(fd, address, length) == 0 && listen(fd, Int32(Self.maxConnections)) == 0
        }
        guard bound == true else {
            let reason = bound == nil ? "경로가 너무 깁니다" : String(cString: strerror(errno))
            Darwin.close(fd)
            throw ListenerError(message: reason)
        }
        _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK)
        self.fd = fd

        acceptSource = DispatchSource.makeReadSource(fileDescriptor: fd, queue: .main)
        acceptSource.setEventHandler { [weak self] in self?.acceptPending() }
        acceptSource.setCancelHandler { Darwin.close(fd) }
        acceptSource.resume()
    }

    func close() {
        connections.values.forEach { $0.close() }
        connections = [:]
        acceptSource.cancel()
        unlink(path)
    }

    func broadcast() {
        let values = IPCActions.values()
        for connection in connections.values {
            guard let template = connection.subscription else { continue }
            if !connection.send(template.render(values)) {
                remove(connection)
            }
        }
    }

    /// Creates the directory (0700) and clears a stale socket. Never takes over a live socket or
    /// deletes a non-socket file.
    private static func prepare(_ path: String) throws(ListenerError) {
        let directory = (path as NSString).deletingLastPathComponent
        do {
            try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true,
                                                    attributes: [.posixPermissions: 0o700])
        } catch {
            throw ListenerError(message: "디렉터리를 만들 수 없습니다: \(error.localizedDescription)")
        }
        var info = stat()
        guard lstat(path, &info) == 0 else { return }
        guard info.st_mode & S_IFMT == S_IFSOCK else {
            throw ListenerError(message: "소켓이 아닌 파일이 이미 있습니다")
        }
        if isLive(path) {
            throw ListenerError(message: "다른 프로세스가 사용 중입니다")
        }
        unlink(path)
    }

    private static func isLive(_ path: String) -> Bool {
        let fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return false }
        defer { Darwin.close(fd) }
        return withAddress(path) { address, length in connect(fd, address, length) == 0 } ?? false
    }

    /// nil if the path doesn't fit in sockaddr_un.
    private static func withAddress<T>(_ path: String, _ body: (UnsafePointer<sockaddr>, socklen_t) -> T) -> T? {
        var address = sockaddr_un()
        let bytes = Array(path.utf8)
        guard bytes.count < MemoryLayout.size(ofValue: address.sun_path) else { return nil }
        address.sun_family = sa_family_t(AF_UNIX)
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        withUnsafeMutableBytes(of: &address.sun_path) { buffer in
            buffer.copyBytes(from: bytes)
            buffer[bytes.count] = 0
        }
        return withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                body($0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
    }

    private func acceptPending() {
        while true {
            let client = accept(fd, nil, nil)
            guard client >= 0 else { return }  // EAGAIN: drained
            guard connections.count < Self.maxConnections else {
                Darwin.close(client)
                continue
            }
            let connection = Connection(fd: client)
            connections[ObjectIdentifier(connection)] = connection
            connection.start(
                timeout: Self.readTimeout,
                maxLineBytes: Self.maxLineBytes,
                onLine: { [weak self, weak connection] line in
                    guard let self, let connection else { return }
                    self.handle(line, from: connection)
                },
                onClose: { [weak self, weak connection] in
                    guard let self, let connection else { return }
                    self.remove(connection)
                }
            )
        }
    }

    private func handle(_ line: String, from connection: Connection) {
        let name = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let request = requests[name] else {
            _ = connection.send(name.isEmpty ? "err empty-request" : "err unknown-request")
            remove(connection)
            return
        }
        let values = IPCActions.perform(request.action)
        let delivered = connection.send(request.reply.render(values))
        if request.action == .subscribe, delivered {
            connection.subscription = request.reply
        } else {
            remove(connection)
        }
    }

    private func remove(_ connection: Connection) {
        connection.close()
        connections[ObjectIdentifier(connection)] = nil
    }
}

// MARK: - Connection

private final class Connection {
    let fd: Int32
    /// Set once the client subscribed; the connection then stays open.
    var subscription: ReplyTemplate?
    private var readSource: DispatchSourceRead?
    private var buffer = Data()
    private var closed = false
    /// The read source's cancel handler has run.
    private var readFinished = false

    init(fd: Int32) {
        self.fd = fd
        var on: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
        _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK)
    }

    func start(timeout: TimeInterval, maxLineBytes: Int,
               onLine: @escaping (String) -> Void, onClose: @escaping () -> Void) {
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: .main)
        source.setEventHandler { [weak self] in
            guard let self else { return }
            var chunk = [UInt8](repeating: 0, count: 1024)
            let count = read(self.fd, &chunk, chunk.count)
            if count < 0 {
                if errno != EAGAIN { onClose() }
                return
            }
            if count == 0 {
                if self.subscription != nil {
                    // Half-closed subscriber (e.g. `nc <<< subscribe`): stop reading, keep
                    // writing. A peer that is really gone fails the next write and is dropped.
                    self.stopReading()
                } else if !self.buffer.isEmpty {
                    // A request without a trailing newline still counts.
                    onLine(String(decoding: self.buffer, as: UTF8.self))
                } else {
                    onClose()
                }
                return
            }
            guard self.subscription == nil else { return }  // subscribers don't send requests
            self.buffer.append(contentsOf: chunk[0..<count])
            if let newline = self.buffer.firstIndex(of: UInt8(ascii: "\n")) {
                let line = String(decoding: self.buffer[..<newline], as: UTF8.self)
                self.buffer.removeAll()
                onLine(line)
            } else if self.buffer.count > maxLineBytes {
                _ = self.send("err line-too-long")
                onClose()
            }
        }
        // The fd may only be closed once the read source's cancel handler has run; whichever of
        // the handler and close() comes second closes it.
        source.setCancelHandler { [weak self, fd] in
            guard let self else {
                Darwin.close(fd)
                return
            }
            self.readFinished = true
            if self.closed { Darwin.close(fd) }
        }
        readSource = source
        source.resume()

        DispatchQueue.main.asyncAfter(deadline: .now() + timeout) { [weak self] in
            guard let self, !self.closed, self.subscription == nil else { return }
            onClose()
        }
    }

    /// Writes one line; false if the peer is gone or not reading (subscribers get dropped).
    func send(_ line: String) -> Bool {
        guard !closed else { return false }
        let data = Array((line + "\n").utf8)
        return data.withUnsafeBytes { write(fd, $0.baseAddress, $0.count) } == data.count
    }

    func close() {
        guard !closed else { return }
        closed = true
        if let readSource {
            readSource.cancel()  // its cancel handler closes the fd
            self.readSource = nil
        } else if readFinished {
            Darwin.close(fd)
        }
        // Otherwise a cancel from stopReading() is pending and its handler closes the fd.
    }

    private func stopReading() {
        readSource?.cancel()  // not closed, so the handler leaves the fd open for writing
        readSource = nil
    }
}
