import Foundation

/// What a socket request does. Users name requests freely; the actions are fixed.
public enum IPCAction: Equatable, Sendable {
    case ping
    case version
    case get
    case set(IPCMode)
    case toggle
    case subscribe

    public enum IPCMode: String, Sendable {
        case en
        case ko
    }

    static let names = ["ping", "version", "get", "set en", "set ko", "toggle", "subscribe"]

    init?(_ string: String) {
        switch string {
        case "ping": self = .ping
        case "version": self = .version
        case "get": self = .get
        case "set en": self = .set(.en)
        case "set ko": self = .set(.ko)
        case "toggle": self = .toggle
        case "subscribe": self = .subscribe
        default: return nil
        }
    }
}

/// Reply text with `{variable}` placeholders, validated at parse time.
public struct ReplyTemplate: Equatable, Sendable {
    public let text: String

    /// mode: en|ko, app: focused bundle ID ("-" if unknown), result: switched|noop,
    /// active: active|inactive (kbd is the selected input source), version: kbd version.
    public static let variables = ["mode", "app", "result", "active", "version"]

    init(_ text: String) throws(TemplateError) {
        var rest = Substring(text)
        while let open = rest.firstIndex(of: "{") {
            guard let close = rest[open...].firstIndex(of: "}") else { throw .unclosedBrace }
            let name = String(rest[rest.index(after: open)..<close])
            guard Self.variables.contains(name) else { throw .unknownVariable(name) }
            rest = rest[rest.index(after: close)...]
        }
        self.text = text
    }

    public func render(_ values: [String: String]) -> String {
        var output = text
        for name in Self.variables {
            output = output.replacingOccurrences(of: "{\(name)}", with: values[name] ?? "")
        }
        return output
    }

    enum TemplateError: Error {
        case unclosedBrace
        case unknownVariable(String)
    }
}

public struct IPCRequest: Equatable, Sendable {
    public var action: IPCAction
    public var reply: ReplyTemplate
}

/// A listening socket and the requests it understands (built-ins plus the user's additions).
public struct IPCSocket: Equatable, Sendable {
    /// Absolute path, `~` expanded.
    public var path: String
    /// Keyed by the exact request line.
    public var requests: [String: IPCRequest]

    public static let defaultPath = "~/.local/state/kbd/kbd.sock"

    public static let builtinRequests: [String: IPCRequest] = {
        func request(_ action: IPCAction, _ reply: String) -> IPCRequest {
            IPCRequest(action: action, reply: try! ReplyTemplate(reply))
        }
        return [
            "ping": request(.ping, "pong"),
            "version": request(.version, "ok kbd {version} proto 1"),
            "get": request(.get, "ok {mode} {app} {active}"),
            "set en": request(.set(.en), "ok {result} {active}"),
            "set ko": request(.set(.ko), "ok {result} {active}"),
            "switch": request(.set(.en), "ok {result} {active}"),
            "toggle": request(.toggle, "ok {mode} {active}"),
            // Sent once on subscribe, then on every change.
            "subscribe": request(.subscribe, "mode {mode} {app} {active}"),
        ]
    }()

    public init(path: String, requests: [String: IPCRequest] = IPCSocket.builtinRequests) {
        self.path = path
        self.requests = requests
    }

    static func expand(_ path: String, home: String = NSHomeDirectory()) -> String {
        if path == "~" { return home }
        if path.hasPrefix("~/") { return home + path.dropFirst() }
        return path
    }
}
