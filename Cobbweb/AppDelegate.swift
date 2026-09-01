// AppDelegate.swift
// Manages the NSStatusItem, NSPopover, and the Preferences window.
// Compatible with macOS 12.0+.

import AppKit
import SwiftUI

// MARK: - Notification Names

extension Notification.Name {
    static let closePopover    = Notification.Name("com.cobbweb.closePopover")
    static let openPreferences = Notification.Name("com.cobbweb.openPreferences")
    static let openAbout       = Notification.Name("com.cobbweb.openAbout")
}

// MARK: - AppDelegate

final class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var preferencesWindow: NSWindow?
    internal let clipboardMonitor = ClipboardMonitor()
    internal let loginItemManager = LoginItemManager()
    private var eventMonitor: Any?

    // MARK: - Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()
        setupPopover()
        setupEventMonitor()
        setupCloseObserver()
        setupActionObservers()
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
        }
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Status Item

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        guard let button = statusItem.button else { return }

        // Load custom cobweb icon from asset catalog.
        // isTemplate = true lets macOS tint it for light/dark menu bar.
        if let cobwebImage = NSImage(named: "micon") {
            cobwebImage.isTemplate = true
            button.image = cobwebImage
        } else {
            button.image = NSImage(
                systemSymbolName: "network",
                accessibilityDescription: "Cobbweb"
            )
        }
        button.action = #selector(togglePopover)
        button.target = self
    }

    // MARK: - Action Observers

    private func setupActionObservers() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(openPreferences),
            name: .openPreferences,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(openAbout),
            name: .openAbout,
            object: nil
        )
    }

    // MARK: - Menu Actions

    @objc private func openPreferences() {
        if let existing = preferencesWindow, existing.isVisible {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let prefsView = PreferencesView()
            .environmentObject(loginItemManager)
            .environmentObject(clipboardMonitor)

        let hostingController = NSHostingController(rootView: prefsView)

        let window = NSWindow(contentViewController: hostingController)
        window.title = "Cobbweb Preferences"
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.setContentSize(NSSize(width: 400, height: 360))
        window.center()
        window.isReleasedWhenClosed = false

        preferencesWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func openAbout() {
        NSApp.orderFrontStandardAboutPanel(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - Popover

    private func setupPopover() {
        let contentView = ContentView()
            .environmentObject(clipboardMonitor)
            .environmentObject(loginItemManager)

        let hostingController = NSHostingController(rootView: contentView)
        hostingController.view.frame = NSRect(x: 0, y: 0, width: 320, height: 560)

        popover = NSPopover()
        popover.contentSize = NSSize(width: 320, height: 560)
        popover.behavior = .transient
        popover.animates = true
        popover.contentViewController = hostingController
    }

    // MARK: - Event Monitor

    private func setupEventMonitor() {
        eventMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            guard let self, self.popover.isShown else { return }
            self.closePopover()
        }
    }

    // MARK: - Close Observer

    private func setupCloseObserver() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleClosePopover),
            name: .closePopover,
            object: nil
        )
    }

    @objc private func handleClosePopover() {
        closePopover()
    }

    // MARK: - Popover Toggle

    @objc private func togglePopover() {
        if popover.isShown {
            closePopover()
        } else {
            openPopover()
        }
    }

    private func openPopover() {
        guard let button = statusItem.button else { return }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    private func closePopover() {
        popover.performClose(nil)
    }
}
