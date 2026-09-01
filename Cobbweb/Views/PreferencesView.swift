// PreferencesView.swift
// Standalone preferences window content. Compatible with macOS 12+.

import SwiftUI
import AppKit

struct PreferencesView: View {

    @EnvironmentObject private var loginItemManager: LoginItemManager
    @EnvironmentObject private var monitor: ClipboardMonitor

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            preferenceSection("General") {
                launchAtLoginRow
                Divider()
                maxLinksRow
                Divider()
                visibleLinksRow
            }

            preferenceSection("Storage") {
                storageInfoRow
                Divider()
                clearAllRow
            }

            preferenceSection("About") {
                versionRow
                Divider()
                privacyRow
            }
        }
        .padding(20)
        .frame(width: 400)
    }

    // MARK: - Section Builder

    private func preferenceSection<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.headline)
                .padding(.bottom, 8)

            VStack(spacing: 0) {
                content()
            }
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.primary.opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
            )
        }
        .padding(.bottom, 20)
    }

    // MARK: - Row Helper

    private func prefRow<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
    }

    // MARK: - Launch at Login

    private var launchAtLoginRow: some View {
        prefRow {
            HStack {
                Label("Launch at Login", systemImage: "arrow.clockwise.circle")
                    .foregroundStyle(.primary)
                Spacer()
                Toggle(isOn: $loginItemManager.launchAtLogin) {
                    EmptyView()
                }
                .toggleStyle(.switch)
                .labelsHidden()
                .controlSize(.small)
            }
        }
    }

    // MARK: - Max Links

    private var maxLinksRow: some View {
        prefRow {
            HStack {
                Label("Links to keep", systemImage: "list.number")
                    .foregroundStyle(.primary)
                Spacer()
                Stepper("\(monitor.maxLinks)", value: $monitor.maxLinks, in: 10...200, step: 10)
                    .frame(width: 120)
            }
        }
    }

    // MARK: - Visible Links

    private var visibleLinksRow: some View {
        prefRow {
            HStack {
                Label("Links visible at once", systemImage: "eye")
                    .foregroundStyle(.primary)
                Spacer()
                Stepper("\(monitor.visibleLinks)", value: $monitor.visibleLinks, in: 3...20, step: 1)
                    .frame(width: 120)
            }
        }
    }

    // MARK: - Storage Info

    private var storageInfoRow: some View {
        prefRow {
            HStack {
                Label("Saved links", systemImage: "link.circle")
                    .foregroundStyle(.primary)
                Spacer()
                Text("\(monitor.links.count)")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
    }

    // MARK: - Clear All

    private var clearAllRow: some View {
        prefRow {
            HStack {
                Label("Clear all saved links", systemImage: "trash")
                    .foregroundStyle(.primary)
                Spacer()
                Button("Clear All") {
                    monitor.clearAll()
                }
                .foregroundColor(.red)
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Version

    private var versionRow: some View {
        prefRow {
            HStack {
                Label("Version", systemImage: "info.circle")
                    .foregroundStyle(.primary)
                Spacer()
                Text(appVersion)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
    }

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
        let build   = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }

    // MARK: - Privacy

    private var privacyRow: some View {
        prefRow {
            HStack {
                Label("Privacy Policy", systemImage: "hand.raised")
                    .foregroundStyle(.primary)
                Spacer()
                Button("View") {
                    if let url = URL(string: "https://yourwebsite.com/privacy") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .buttonStyle(.plain)
                .foregroundColor(.accentColor)
            }
        }
    }
}
