// main.swift — CobbwebHelper
// Minimal login item helper. Launched at login by macOS on macOS 12.
// Checks if Cobbweb is running. If not, launches it. Then exits immediately.

import AppKit

let mainBundleID = "com.yourteam.cobbweb"

let isRunning = NSWorkspace.shared.runningApplications
    .contains { $0.bundleIdentifier == mainBundleID }

if !isRunning {
    // Walk up from Helper.app → LoginItems → Library → Contents → Cobbweb.app
    var url = Bundle.main.bundleURL
    for _ in 0..<4 { url = url.deletingLastPathComponent() }

    NSWorkspace.shared.openApplication(
        at: url,
        configuration: .init(),
        completionHandler: nil
    )
}

exit(0)
