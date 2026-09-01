// ContentView.swift
import SwiftUI

struct ContentView: View {

    @EnvironmentObject private var monitor: ClipboardMonitor
    @EnvironmentObject private var loginItemManager: LoginItemManager

    // MARK: - Height calculation

    /// Height of a single link row (padding 6pt top + 6pt bottom + 26pt content + 2pt buffer).
    private let rowHeight: CGFloat = 40
    /// Height of a single divider between rows.
    private let dividerHeight: CGFloat = 1
    /// Max fully visible rows — driven by user preference.
    private var maxVisibleRows: Int { monitor.visibleLinks }
    /// Minimum visible rows — ensures the list never looks too cramped.
    private let minVisibleRows: Int = 3
    /// Height of a search section header ("Exact Matches" / "Related").
    private let sectionHeaderHeight: CGFloat = 24

    /// Fixed chrome: header + search bar + 3 dividers + 3 menu rows.
    private var chromeHeight: CGFloat {
        let header: CGFloat = 28
        let searchBar: CGFloat = 29
        let dividers: CGFloat = 3
        let menuRows: CGFloat = 3 * 29
        return header + searchBar + dividers + menuRows
    }

    /// Empty state height when no links.
    private var emptyStateHeight: CGFloat { 68 }

    private var idealHeight: CGFloat {
        let count = monitor.displayedLinks.count
        if count == 0 {
            return chromeHeight + emptyStateHeight
        }

        // When searching, add section header height(s) to avoid squeezing rows.
        var sectionHeadersHeight: CGFloat = 0
        if !monitor.searchText.isEmpty {
            let hasExact   = monitor.searchResults.contains { $0.category == .exact }
            let hasRelated = monitor.searchResults.contains { $0.category == .related }
            if hasExact   { sectionHeadersHeight += sectionHeaderHeight }
            if hasRelated { sectionHeadersHeight += sectionHeaderHeight }
        }

        // Show at least minVisibleRows, up to maxVisibleRows.
        let visibleRows = min(max(count, minVisibleRows), maxVisibleRows)
        let listHeight = (CGFloat(visibleRows) * rowHeight)
                       + (CGFloat(visibleRows - 1) * dividerHeight)
                       + sectionHeadersHeight
        return chromeHeight + listHeight
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            searchBar
            Divider()
            linkList
            Divider()
            menuList
        }
        .frame(width: 320, height: idealHeight)
        .background(.ultraThinMaterial)
        .animation(.easeInOut(duration: 0.2), value: monitor.displayedLinks.count)
        .animation(.easeInOut(duration: 0.2), value: monitor.searchText.isEmpty)
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text("Cobbweb")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.primary)

            Spacer()

            if !monitor.links.isEmpty {
                Button(role: .destructive) {
                    confirmClearAll()
                } label: {
                    Text("Clear")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
    }

    // MARK: - Search Bar

    private var searchBar: some View {
        HStack(spacing: 5) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)

            TextField("Search…", text: $monitor.searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .disableAutocorrection(true)

            if !monitor.searchText.isEmpty {
                Button {
                    monitor.searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    // MARK: - Link List

    @ViewBuilder
    private var linkList: some View {
        if monitor.displayedLinks.isEmpty {
            emptyState
        } else if monitor.searchText.isEmpty {
            // No search active — plain list, no section headers.
            plainList(monitor.searchResults)
        } else {
            // Search active — split into Exact Matches and Related sections.
            let exact   = monitor.searchResults.filter { $0.category == .exact }
            let related = monitor.searchResults.filter { $0.category == .related }
            ScrollView {
                LazyVStack(spacing: 0) {
                    if !exact.isEmpty {
                        sectionHeader("Exact Matches")
                        rowGroup(exact)
                    }
                    if !related.isEmpty {
                        if !exact.isEmpty { Divider() }
                        sectionHeader("Related")
                        rowGroup(related)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func plainList(_ results: [SearchResult]) -> some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                rowGroup(results)
            }
        }
    }

    @ViewBuilder
    private func rowGroup(_ results: [SearchResult]) -> some View {
        ForEach(results, id: \.link.id) { result in
            LinkRowView(link: result.link) {
                openInBrowser(result.link)
            } onPin: {
                result.link.isPinned
                    ? monitor.unpin(id: result.link.id)
                    : monitor.pin(id: result.link.id)
            } onDelete: {
                withAnimation { monitor.remove(id: result.link.id) }
            }
            if result.link.id != results.last?.link.id {
                Divider().padding(.leading, 46)
            }
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.top, 6)
            .padding(.bottom, 2)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: monitor.searchText.isEmpty ? "doc.on.clipboard" : "magnifyingglass")
                .font(.system(size: 20))
                .foregroundStyle(.tertiary)
            Text(monitor.searchText.isEmpty
                 ? "Copy a web link to get started"
                 : "No results for \"\(monitor.searchText)\"")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
    }

    // MARK: - Menu List

    private var menuList: some View {
        VStack(spacing: 0) {
            MenuRowItem(title: "Preferences", icon: "gearshape") {
                NotificationCenter.default.post(name: .openPreferences, object: nil)
            }
            Divider().padding(.leading, 34)
            MenuRowItem(title: "About", icon: "info.circle") {
                NotificationCenter.default.post(name: .openAbout, object: nil)
            }
            Divider().padding(.leading, 34)
            MenuRowItem(title: "Quit", icon: "power", destructive: true) {
                NSApplication.shared.terminate(nil)
            }
        }
    }

    // MARK: - Actions

    private func confirmClearAll() {
        let alert = NSAlert()
        alert.messageText = "Clear All Links?"
        alert.informativeText = "This will permanently delete all \(monitor.links.count) saved links. This action cannot be undone."
        alert.alertStyle = .warning

        // Destructive action — red button on macOS.
        alert.addButton(withTitle: "Delete All")
        alert.addButton(withTitle: "Cancel")

        // Style the first button as destructive.
        if let deleteButton = alert.buttons.first {
            deleteButton.hasDestructiveAction = true
        }

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            withAnimation { monitor.clearAll() }
        }
    }

    private func openInBrowser(_ link: SavedLink) {
        NSWorkspace.shared.open(link.rawURL)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            NotificationCenter.default.post(name: .closePopover, object: nil)
        }
    }
}
