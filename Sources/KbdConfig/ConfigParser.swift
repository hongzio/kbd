import Foundation
import KbdCore
import TOMLDecoder

public struct ParsedConfig: Sendable {
    public var config: Config
    /// Non-fatal issues such as unknown keys (likely typos).
    public var warnings: [String]
}

/// The file can't be used; the caller keeps the previous config.
public struct ConfigError: Error, Equatable, CustomStringConvertible {
    public var messages: [String]
    public var description: String { messages.joined(separator: "\n") }
}

public enum ConfigParser {
    public static func parse(_ source: String) throws(ConfigError) -> ParsedConfig {
        let raw: RawConfig
        do {
            raw = try TOMLDecoder().decode(RawConfig.self, from: source)
        } catch {
            throw ConfigError(messages: [describe(error)])
        }

        var errors: [String] = []
        var config = Config()

        func value<T>(_ path: String, _ string: String?, _ convert: (String) -> T?, expected: [String]) -> T? {
            guard let string else { return nil }
            if let converted = convert(string) { return converted }
            errors.append("\(path): \"\(string)\"은(는) 사용할 수 없습니다. 가능한 값: \(expected.joined(separator: ", "))")
            return nil
        }

        if let toggle = raw.toggle {
            if let key = value("toggle.key", toggle.key, ToggleKey.init(name:), expected: ToggleKey.allNames) {
                config.toggle.key = key
            }
            if let target = value("toggle.remap_to", toggle.remapTo,
                                  { ToggleKey(name: $0).flatMap { $0.isFunctionKey ? $0 : nil } },
                                  expected: ToggleKey.functionKeyNames) {
                config.toggle.remapTo = target
            }
        }
        if let hangul = raw.hangul {
            if let layout = value("hangul.layout", hangul.layout, { Layout.builtIn($0)?.id },
                                  expected: Layout.builtInIDs) {
                config.hangul.layout = layout
            }
            if let unit = value("hangul.backspace", hangul.backspace, BackspaceUnit.init(rawValue:),
                                expected: [BackspaceUnit.jamo, .syllable].map(\.rawValue)) {
                config.hangul.backspace = unit
            }
        }
        if let escape = raw.escape {
            if let enabled = escape.enabled { config.escape.enabled = enabled }
            if let keys = escape.keys {
                let expected = Config.EscapeKey.allCases.map(\.rawValue)
                config.escape.keys = keys.compactMap {
                    value("escape.keys", $0, Config.EscapeKey.init(rawValue:), expected: expected)
                }
            }
        }
        if let newApp = value("mode.new_app", raw.mode?.newApp, Config.NewAppMode.init(rawValue:),
                              expected: Config.NewAppMode.allCases.map(\.rawValue)) {
            config.mode.newApp = newApp
        }
        for (bundleID, app) in raw.apps ?? [:] {
            var policy = Config.AppPolicy()
            if let onActivate = value("apps.\"\(bundleID)\".on_activate", app.onActivate,
                                      Config.OnActivate.init(rawValue:),
                                      expected: Config.OnActivate.allCases.map(\.rawValue)) {
                policy.onActivate = onActivate
            }
            policy.escape = app.escape
            config.apps[bundleID] = policy
        }

        if let sockets = raw.ipc?.socket {
            var seen: Set<String> = []
            config.ipcSockets = []
            for (index, rawSocket) in sockets.enumerated() {
                let where_ = "ipc.socket[\(index)]"
                guard let path = rawSocket.path, path.hasPrefix("/") || path.hasPrefix("~") else {
                    errors.append("\(where_).path: 절대 경로(/ 또는 ~로 시작)가 필요합니다")
                    continue
                }
                let expanded = IPCSocket.expand(path)
                guard seen.insert(expanded).inserted else {
                    errors.append("\(where_).path: \"\(path)\"이(가) 중복되었습니다")
                    continue
                }
                var requests = IPCSocket.builtinRequests
                for (name, rawRequest) in rawSocket.requests ?? [:] {
                    let at = "\(where_).requests.\"\(name)\""
                    guard !name.isEmpty else {
                        errors.append("\(at): 요청 이름이 비어 있습니다")
                        continue
                    }
                    guard let actionName = rawRequest.action else {
                        errors.append("\(at).action: 값이 없습니다. 가능한 값: \(IPCAction.names.joined(separator: ", "))")
                        continue
                    }
                    guard let action = value("\(at).action", actionName, IPCAction.init, expected: IPCAction.names) else {
                        continue
                    }
                    // Without a reply, reuse the built-in reply for the same action.
                    let fallback = IPCSocket.builtinRequests.values.first { $0.action == action }!.reply
                    var reply = fallback
                    if let text = rawRequest.reply {
                        do {
                            reply = try ReplyTemplate(text)
                        } catch {
                            switch error {
                            case .unclosedBrace:
                                errors.append("\(at).reply: 닫히지 않은 {가 있습니다")
                            case .unknownVariable(let name):
                                let known = ReplyTemplate.variables.map { "{\($0)}" }.joined(separator: ", ")
                                errors.append("\(at).reply: 알 수 없는 변수 {\(name)}. 가능한 변수: \(known)")
                            }
                            continue
                        }
                    }
                    requests[name] = IPCRequest(action: action, reply: reply)
                }
                config.ipcSockets.append(IPCSocket(path: expanded, requests: requests))
            }
        }

        guard errors.isEmpty else { throw ConfigError(messages: errors) }
        let warnings = raw.unknownKeys.sorted().map { "\($0): 알 수 없는 설정입니다 (오타인지 확인하세요)" }
        return ParsedConfig(config: config, warnings: warnings)
    }

    private static func describe(_ error: Error) -> String {
        // TOMLDecoder reports type errors with its own error type, including the line number.
        guard let decodingError = error as? DecodingError else { return "TOML 오류: \(error)" }
        switch decodingError {
        case .typeMismatch(_, let context), .valueNotFound(_, let context):
            return "\(path(context.codingPath)): 값의 형식이 올바르지 않습니다"
        case .dataCorrupted(let context):
            if let underlying = context.underlyingError {
                return "TOML 문법 오류: \(underlying)"
            }
            return "\(path(context.codingPath)): \(context.debugDescription)"
        case .keyNotFound(let key, let context):
            return "\(path(context.codingPath + [key])): 값이 없습니다"
        @unknown default:
            return "\(decodingError)"
        }
    }

    private static func path(_ codingPath: [CodingKey]) -> String {
        codingPath.map(\.stringValue).joined(separator: ".")
    }
}

// MARK: - Raw decoding

/// Decodes the TOML shape as-is (strings unvalidated) and records keys it doesn't know.
private struct RawConfig: Decodable {
    var toggle: RawToggle?
    var hangul: RawHangul?
    var escape: RawEscape?
    var mode: RawMode?
    var apps: [String: RawApp]?
    var ipc: RawIPC?
    var unknownKeys: [String] = []

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        ipc = try c.decodeIfPresent(RawIPC.self, forKey: "ipc")
        toggle = try c.decodeIfPresent(RawToggle.self, forKey: "toggle")
        hangul = try c.decodeIfPresent(RawHangul.self, forKey: "hangul")
        escape = try c.decodeIfPresent(RawEscape.self, forKey: "escape")
        mode = try c.decodeIfPresent(RawMode.self, forKey: "mode")
        apps = try c.decodeIfPresent([String: RawApp].self, forKey: "apps")

        unknownKeys = unknown(c, known: ["toggle", "hangul", "escape", "mode", "apps", "ipc"])
        unknownKeys += (toggle?.unknownKeys ?? []).map { "toggle.\($0)" }
        unknownKeys += (hangul?.unknownKeys ?? []).map { "hangul.\($0)" }
        unknownKeys += (escape?.unknownKeys ?? []).map { "escape.\($0)" }
        unknownKeys += (mode?.unknownKeys ?? []).map { "mode.\($0)" }
        for (bundleID, app) in apps ?? [:] {
            unknownKeys += app.unknownKeys.map { "apps.\"\(bundleID)\".\($0)" }
        }
        unknownKeys += (ipc?.unknownKeys ?? []).map { "ipc.\($0)" }
        for (index, socket) in (ipc?.socket ?? []).enumerated() {
            unknownKeys += socket.unknownKeys.map { "ipc.socket[\(index)].\($0)" }
            for (name, request) in socket.requests ?? [:] {
                unknownKeys += request.unknownKeys.map { "ipc.socket[\(index)].requests.\"\(name)\".\($0)" }
            }
        }
    }
}

private struct RawIPC: Decodable {
    var socket: [RawSocket]?
    var unknownKeys: [String]

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        socket = try c.decodeIfPresent([RawSocket].self, forKey: "socket")
        unknownKeys = unknown(c, known: ["socket"])
    }
}

private struct RawSocket: Decodable {
    var path: String?
    var requests: [String: RawRequest]?
    var unknownKeys: [String]

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        path = try c.decodeIfPresent(String.self, forKey: "path")
        requests = try c.decodeIfPresent([String: RawRequest].self, forKey: "requests")
        unknownKeys = unknown(c, known: ["path", "requests"])
    }
}

private struct RawRequest: Decodable {
    var action: String?
    var reply: String?
    var unknownKeys: [String]

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        action = try c.decodeIfPresent(String.self, forKey: "action")
        reply = try c.decodeIfPresent(String.self, forKey: "reply")
        unknownKeys = unknown(c, known: ["action", "reply"])
    }
}

private struct RawToggle: Decodable {
    var key: String?
    var remapTo: String?
    var unknownKeys: [String]

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        key = try c.decodeIfPresent(String.self, forKey: "key")
        remapTo = try c.decodeIfPresent(String.self, forKey: "remap_to")
        unknownKeys = unknown(c, known: ["key", "remap_to"])
    }
}

private struct RawHangul: Decodable {
    var layout: String?
    var backspace: String?
    var unknownKeys: [String]

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        layout = try c.decodeIfPresent(String.self, forKey: "layout")
        backspace = try c.decodeIfPresent(String.self, forKey: "backspace")
        unknownKeys = unknown(c, known: ["layout", "backspace"])
    }
}

private struct RawEscape: Decodable {
    var enabled: Bool?
    var keys: [String]?
    var unknownKeys: [String]

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        enabled = try c.decodeIfPresent(Bool.self, forKey: "enabled")
        keys = try c.decodeIfPresent([String].self, forKey: "keys")
        unknownKeys = unknown(c, known: ["enabled", "keys"])
    }
}

private struct RawMode: Decodable {
    var newApp: String?
    var unknownKeys: [String]

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        newApp = try c.decodeIfPresent(String.self, forKey: "new_app")
        unknownKeys = unknown(c, known: ["new_app"])
    }
}

private struct RawApp: Decodable {
    var onActivate: String?
    var escape: Bool?
    var unknownKeys: [String]

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        onActivate = try c.decodeIfPresent(String.self, forKey: "on_activate")
        escape = try c.decodeIfPresent(Bool.self, forKey: "escape")
        unknownKeys = unknown(c, known: ["on_activate", "escape"])
    }
}

private struct AnyKey: CodingKey, ExpressibleByStringLiteral {
    var stringValue: String
    var intValue: Int? { nil }
    init(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { nil }
    init(stringLiteral value: String) { stringValue = value }
}

private func unknown(_ container: KeyedDecodingContainer<AnyKey>, known: Set<String>) -> [String] {
    container.allKeys.map(\.stringValue).filter { !known.contains($0) }
}
