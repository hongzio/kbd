// Registers the installed bundle with TIS so Info.plist changes (modes, icon labels) take effect.
// Usage: swift scripts/register.swift <path-to-kbd.app>
import Carbon
import Foundation

let url = URL(fileURLWithPath: CommandLine.arguments[1]) as CFURL
let status = TISRegisterInputSource(url)
print("TISRegisterInputSource status=\(status)")
exit(status == noErr ? 0 : 1)
