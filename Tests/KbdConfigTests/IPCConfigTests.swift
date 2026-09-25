import Foundation
import Testing
@testable import KbdConfig

@Suite("IPC config")
struct IPCConfigTests {
    private let home = NSHomeDirectory()

    @Test func defaultIsOneSocketWithBuiltins() throws {
        let sockets = try ConfigParser.parse("").config.ipcSockets
        #expect(sockets.count == 1)
        #expect(sockets[0].path == home + "/.local/state/kbd/kbd.sock")
        #expect(sockets[0].requests == IPCSocket.builtinRequests)
    }

    @Test func customSocketsAndRequests() throws {
        let parsed = try ConfigParser.parse("""
        [[ipc.socket]]
        path = "~/.local/state/kbd/kbd.sock"

        [[ipc.socket]]
        path = "/tmp/other.sock"
        [ipc.socket.requests]
        "leave-insert" = { action = "set en", reply = "ok {result}" }
        get = { action = "get", reply = "{mode}" }
        "mode?" = { action = "get" }
        """)
        #expect(parsed.warnings.isEmpty)
        let sockets = parsed.config.ipcSockets
        #expect(sockets.map(\.path) == [home + "/.local/state/kbd/kbd.sock", "/tmp/other.sock"])
        #expect(sockets[0].requests == IPCSocket.builtinRequests)

        let other = sockets[1].requests
        #expect(other["leave-insert"]?.action == .set(.en))
        #expect(other["leave-insert"]?.reply.text == "ok {result}")
        #expect(other["get"]?.reply.text == "{mode}")                            // override
        #expect(other["mode?"]?.reply == IPCSocket.builtinRequests["get"]!.reply)  // built-in reply reused
        #expect(other["ping"] != nil)                                            // built-ins kept
    }

    @Test func invalidEntriesAreReported() {
        #expect {
            try ConfigParser.parse("""
            [[ipc.socket]]
            path = "relative.sock"

            [[ipc.socket]]
            path = "/tmp/a.sock"
            [ipc.socket.requests]
            x = { action = "reboot" }
            y = { action = "get", reply = "{colour}" }
            z = { action = "get", reply = "{mode" }

            [[ipc.socket]]
            path = "/tmp/a.sock"
            """)
        } throws: { error in
            let messages = (error as! ConfigError).messages
            return messages.count == 5
                && messages.contains { $0.hasPrefix("ipc.socket[0].path:") }
                && messages.contains { $0.hasPrefix("ipc.socket[1].requests.\"x\".action: \"reboot\"") }
                && messages.contains { $0.hasPrefix("ipc.socket[1].requests.\"y\".reply: 알 수 없는 변수 {colour}") }
                && messages.contains { $0.hasPrefix("ipc.socket[1].requests.\"z\".reply: 닫히지 않은") }
                && messages.contains { $0.hasPrefix("ipc.socket[2].path:") && $0.contains("중복") }
        }
    }

    @Test func unknownIPCKeysAreWarnings() throws {
        let parsed = try ConfigParser.parse("""
        [[ipc.socket]]
        path = "/tmp/a.sock"
        mode = 1
        [ipc.socket.requests]
        x = { action = "get", replay = "oops" }
        """)
        #expect(parsed.warnings.count == 2)
        #expect(parsed.warnings.contains { $0.hasPrefix("ipc.socket[0].mode:") })
        #expect(parsed.warnings.contains { $0.hasPrefix("ipc.socket[0].requests.\"x\".replay:") })
    }

    @Test func templateRendering() throws {
        let template = try ReplyTemplate("ok {mode} {app} {mode}")
        #expect(template.render(["mode": "ko", "app": "com.example"]) == "ok ko com.example ko")
        #expect(try ReplyTemplate("no vars").render([:]) == "no vars")
    }

    @Test func tildeExpansion() {
        #expect(IPCSocket.expand("~/x.sock", home: "/Users/me") == "/Users/me/x.sock")
        #expect(IPCSocket.expand("/abs.sock", home: "/Users/me") == "/abs.sock")
    }
}
