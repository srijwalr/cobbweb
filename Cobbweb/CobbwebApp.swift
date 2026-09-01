// CobbwebApp.swift
// App entry point. All UI is managed by AppDelegate (NSStatusItem + NSPopover).
//
// The SwiftUI App protocol requires at least one Scene.
// Using Settings { EmptyView() } causes macOS 13+ to show an empty
// Settings tab in System Settings. The fix is to use Settings with
// actual content (our PreferencesView) — this replaces the broken
// in-popover preferences and gives macOS 13+ the standard ⌘, shortcut.
// On macOS 12 the Settings scene is ignored entirely.

import SwiftUI

@main
struct CobbwebApp: App {

    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // Wire ⌘, to open our real PreferencesView on macOS 13+.
        // This also removes the empty Settings tab — the scene has content now.
        Settings {
            PreferencesView()
                .environmentObject(appDelegate.clipboardMonitor)
                .environmentObject(appDelegate.loginItemManager)
        }
    }
}
