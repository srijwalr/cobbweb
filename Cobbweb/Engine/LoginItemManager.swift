// LoginItemManager.swift
// Launch at login using launchd plist — works on macOS 12+ with no helper bundle.
//
// Writes a launchd agent plist to ~/Library/LaunchAgents/ and loads/unloads
// it via launchctl. This is the same mechanism used by many macOS menu bar apps.

import Foundation
import AppKit
import ServiceManagement

final class LoginItemManager: ObservableObject {

    let isSupported: Bool = true

    @Published var launchAtLogin: Bool = false {
        didSet {
            guard !isInitialising else { return }
            setLaunchAtLogin(launchAtLogin)
        }
    }

    private var isInitialising = true

    // MARK: - Init

    init() {
        if #available(macOS 13.0, *) {
            launchAtLogin = SMAppService.mainApp.status == .enabled
        } else {
            launchAtLogin = launchdPlistExists()
        }
        isInitialising = false
    }

    // MARK: - Set

    private func setLaunchAtLogin(_ enable: Bool) {
        if #available(macOS 13.0, *) {
            do {
                if enable {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                print("[Cobbweb] SMAppService error: \(error.localizedDescription)")
                revert(to: !enable)
            }
        } else {
            if enable {
                installLaunchdPlist()
            } else {
                removeLaunchdPlist()
            }
        }
    }

    // MARK: - launchd (macOS 12)

    /// Path to the plist file in the user's LaunchAgents directory.
    private var plistURL: URL {
        // When sandbox is disabled this resolves to the real ~/Library/LaunchAgents/
        // where launchd actually watches for agents.
        let home = URL(fileURLWithPath: NSHomeDirectory())
        let launchAgents = home.appendingPathComponent("Library/LaunchAgents", isDirectory: true)
        return launchAgents.appendingPathComponent("com.yourteam.cobbweb.plist")
    }

    private var appPath: String {
        // Use the running app's bundle path so it works from any location.
        Bundle.main.bundlePath
    }

    private func launchdPlistExists() -> Bool {
        FileManager.default.fileExists(atPath: plistURL.path)
    }

    private func installLaunchdPlist() {
        // Create ~/Library/LaunchAgents/ if it doesn't exist.
        try? FileManager.default.createDirectory(
            at: plistURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let plistContent = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
            "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key>
            <string>com.yourteam.cobbweb</string>
            <key>ProgramArguments</key>
            <array>
                <string>\(appPath)/Contents/MacOS/Cobbweb</string>
            </array>
            <key>RunAtLoad</key>
            <true/>
            <key>KeepAlive</key>
            <false/>
            <key>LimitLoadToSessionType</key>
            <string>Aqua</string>
        </dict>
        </plist>
        """

        do {
            try plistContent.write(to: plistURL, atomically: true, encoding: .utf8)
            // Don't call launchctl load here — that would start the app immediately.
            // The plist being present in ~/Library/LaunchAgents/ is enough for
            // macOS to pick it up on next login automatically.
            print("[Cobbweb] Launch at login enabled via launchd ✓")
        } catch {
            print("[Cobbweb] Failed to install launchd plist: \(error.localizedDescription)")
            revert(to: false)
        }
    }

    private func removeLaunchdPlist() {
        guard launchdPlistExists() else { return }
        do {
            try FileManager.default.removeItem(at: plistURL)
            print("[Cobbweb] Launch at login disabled ✓")
        } catch {
            print("[Cobbweb] Failed to remove launchd plist: \(error.localizedDescription)")
            revert(to: true)
        }
    }

    // MARK: - Revert

    private func revert(to value: Bool) {
        isInitialising = true
        DispatchQueue.main.async {
            self.launchAtLogin = value
            self.isInitialising = false
        }
    }
}
