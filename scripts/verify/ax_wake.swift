// SwiftUI builds a window's accessibility tree only after an accessibility client outside the app asks for it.
// The TestDriver reads that tree from inside the app, so the Sandbox runs this once per launch.
import ApplicationServices
import Foundation

guard CommandLine.arguments.count == 2, let pid = pid_t(CommandLine.arguments[1]) else {
    FileHandle.standardError.write(Data("usage: ax_wake <pid>\n".utf8))
    exit(2)
}
guard AXIsProcessTrusted() else {
    FileHandle.standardError.write(Data("not trusted: allow the terminal that runs the checks in System Settings > Privacy & Security > Accessibility\n".utf8))
    exit(3)
}
var windows: CFTypeRef?
let result = AXUIElementCopyAttributeValue(AXUIElementCreateApplication(pid), kAXWindowsAttribute as CFString, &windows)
exit(result == .success ? 0 : 1)
