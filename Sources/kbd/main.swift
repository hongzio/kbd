import AppKit
import InputMethodKit
import KbdConfig

guard let connectionName = Bundle.main.infoDictionary?["InputMethodConnectionName"] as? String,
      let server = IMKServer(name: connectionName, bundleIdentifier: Bundle.main.bundleIdentifier)
else {
    Log.main.fault("failed to start IMKServer")
    exit(1)
}
_ = server

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

// Writes to IPC clients that went away must not kill the IME.
signal(SIGPIPE, SIG_IGN)

ConfigStore.shared.observe { config in
    let toggle = config.toggle
    HIDRemapper.shared.setMapping(from: toggle.needsRemap ? toggle.key : nil, to: toggle.remapTo)
}
// Every load, not just changes: apply() is idempotent and retries sockets that failed before.
ConfigStore.shared.observeLoad {
    IPCServer.shared.apply(ConfigStore.shared.config.ipcSockets)
}
ModeState.shared.observe { IPCServer.shared.broadcast() }
InputSource.observeChanges { IPCServer.shared.broadcast() }

ConfigStore.shared.load()
Log.main.notice("kbd started")

// The remap and socket files outlive this process unless removed; killall/logout send SIGTERM.
signal(SIGTERM, SIG_IGN)
let termination = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
termination.setEventHandler {
    HIDRemapper.shared.remove()
    IPCServer.shared.closeAll()
    exit(0)
}
termination.resume()

StatusIcon.shared.install()

app.run()
