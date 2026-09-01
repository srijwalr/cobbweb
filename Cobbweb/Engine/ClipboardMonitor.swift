// ClipboardMonitor.swift
// Background engine that polls NSPasteboard for new URLs, enriches them
// with metadata via LPMetadataProvider, and persists them via LinkStore.

import AppKit
import Combine
import LinkPresentation
import UniformTypeIdentifiers

final class ClipboardMonitor: ObservableObject {

    // MARK: - Published State

    /// All captured links, newest first.
    @Published var links: [SavedLink] = []

    /// Current search query. Set this from the UI — search runs automatically.
    @Published var searchText: String = ""

    /// Categorised search results for the UI.
    /// Contains .exact and .related categories for grouped rendering.
    @Published private(set) var searchResults: [SearchResult] = []

    /// Flat list of displayed links — derived from searchResults.
    var displayedLinks: [SavedLink] { searchResults.map(\.link) }

    /// Maximum number of links to retain. User-configurable via Preferences.
    @Published var maxLinks: Int = 100 {
        didSet {
            UserDefaults.standard.set(maxLinks, forKey: "maxLinks")
            if links.count > maxLinks {
                links = Array(links.prefix(maxLinks))
                persist()
            }
        }
    }

    /// Number of links visible at once before scrolling. User-configurable via Preferences.
    @Published var visibleLinks: Int = 8 {
        didSet {
            UserDefaults.standard.set(visibleLinks, forKey: "visibleLinks")
        }
    }

    // MARK: - Private

    private var lastChangeCount: Int = NSPasteboard.general.changeCount
    private var pollTimer: Timer?
    private let store: LinkStoring
    private let searchEngine = SemanticSearchEngine()
    private var searchCancellable: AnyCancellable?

    // MARK: - Lifecycle

    /// Production init — uses the shared persistent store.
    convenience init() {
        self.init(store: LinkStore.shared)
    }

    /// Designated init — accepts any LinkStoring for testability.
    init(store: LinkStoring) {
        self.store = store
        // Register defaults so UserDefaults returns 100 on first launch
        // before the user has ever opened Preferences.
        UserDefaults.standard.register(defaults: ["maxLinks": 100, "visibleLinks": 8])
        let saved = UserDefaults.standard.integer(forKey: "maxLinks")
        self.maxLinks = saved > 0 ? saved : 100
        let savedVisible = UserDefaults.standard.integer(forKey: "visibleLinks")
        self.visibleLinks = savedVisible > 0 ? savedVisible : 8
        loadPersistedLinks()
        startPolling()
        startSearchPipeline()
    }

    deinit {
        stopPolling()
        searchCancellable?.cancel()
    }

    // MARK: - Search Pipeline

    /// Observes changes to both `links` and `searchText` and re-runs search.
    /// Debounced by 250 ms so rapid keystrokes don't queue up embedding calls.
    private func startSearchPipeline() {
        searchCancellable = Publishers.CombineLatest($links, $searchText)
            .debounce(for: .milliseconds(250), scheduler: DispatchQueue.main)
            .sink { [weak self] allLinks, query in
                guard let self else { return }
                self.searchEngine.search(query: query, in: allLinks) { results in
                    self.searchResults = results
                }
            }
    }

    // MARK: - Persistence: Load

    /// Reads saved records from disk on a background thread, then publishes
    /// them on main. Kicks off favicon re-fetches for any link missing an icon.
    private func loadPersistedLinks() {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self else { return }
            let records = self.store.load()
            let loaded = records.map { SavedLink(record: $0) }

            DispatchQueue.main.async {
                self.links = loaded
                self.sortLinks()
                // Re-fetch favicons for links that were persisted without one.
                for link in loaded {
                    self.fetchMetadata(for: link, iconOnly: link.title != nil)
                }
            }
        }
    }

    /// Persists the current links array. Called after every mutation.
    private func persist() {
        store.save(links.map(\.record))
    }

    // MARK: - Polling

    private func startPolling() {
        pollTimer = Timer.scheduledTimer(
            withTimeInterval: 1.5,
            repeats: true
        ) { [weak self] _ in
            self?.checkClipboard()
        }
        RunLoop.main.add(pollTimer!, forMode: .common)
    }

    private func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    // MARK: - Clipboard Inspection

    private func checkClipboard() {
        let pasteboard = NSPasteboard.general
        guard pasteboard.changeCount != lastChangeCount else { return }
        lastChangeCount = pasteboard.changeCount

        guard let url = extractURL(from: pasteboard) else { return }
        if links.contains(where: { $0.rawURL == url }) { return }

        let newLink = SavedLink(url: url)
        addLink(newLink)
        fetchMetadata(for: newLink, iconOnly: false)
    }

    /// Internal so it can be exercised directly in unit tests.
    func extractURL(from pasteboard: NSPasteboard) -> URL? {
        if let urlString = pasteboard.string(forType: .URL),
           let url = URL(string: urlString), url.isWebURL {
            return url
        }
        if let rawString = pasteboard.string(forType: .string) {
            let trimmed = rawString.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.contains("\n"), !trimmed.contains("\r") else { return nil }
            if let url = URL(string: trimmed), url.isWebURL {
                return url
            }
        }
        return nil
    }

    // MARK: - Link Management

    private func addLink(_ link: SavedLink) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.links.insert(link, at: 0)
            if self.links.count > self.maxLinks {
                self.links = Array(self.links.prefix(self.maxLinks))
            }
            self.sortLinks()
            self.persist()
        }
    }

    /// Updates title and/or icon for an existing link, then persists.
    private func updateLink(id: UUID, title: String?, icon: NSImage?) {
        DispatchQueue.main.async { [weak self] in
            guard let self,
                  let index = self.links.firstIndex(where: { $0.id == id }) else { return }

            var changed = false

            if let title, self.links[index].title != title {
                self.links[index].title = title
                changed = true
            }
            if let icon {
                self.links[index].iconImage = icon
                // iconImage is not persisted, so no need to call persist() for icon-only updates.
            }
            // Only write to disk when text metadata changed.
            if changed { self.persist() }
        }
    }

    // MARK: - Metadata Fetching

    /// Fetches metadata for a link.
    /// - Parameter iconOnly: When true (re-fetch on launch), skip updating the title
    ///   since it was already persisted — only load the favicon into memory.
    private func fetchMetadata(for link: SavedLink, iconOnly: Bool) {
        let provider = LPMetadataProvider()
        provider.shouldFetchSubresources = true

        provider.startFetchingMetadata(for: link.rawURL) { [weak self] metadata, error in
            guard let self else { return }

            if let error {
                print("[Cobbweb] Metadata fetch failed for \(link.rawURL): \(error.localizedDescription)")
                // Still try the favicon fallback even if full metadata failed.
                self.fetchFaviconFallback(for: link, title: nil)
                return
            }

            guard let metadata else { return }

            let title: String? = iconOnly ? nil : metadata.title

            if let imageProvider = metadata.iconProvider {
                imageProvider.loadFileRepresentation(
                    forTypeIdentifier: UTType.image.identifier
                ) { url, _ in
                    var icon: NSImage?
                    if let url, let data = try? Data(contentsOf: url) {
                        icon = NSImage(data: data)
                    }

                    if let icon {
                        // LPMetadataProvider returned a usable icon.
                        self.updateLink(id: link.id, title: title, icon: icon)
                    } else {
                        // Provider gave us an iconProvider but loading failed —
                        // fall back to the favicon service.
                        self.fetchFaviconFallback(for: link, title: title)
                    }
                }
            } else {
                // No iconProvider at all (common for Google, YouTube, etc.)
                // Try the favicon service before giving up.
                self.fetchFaviconFallback(for: link, title: title)
            }
        }
    }

    /// Fetches a favicon via Google's public favicon service.
    /// Works reliably for domains that block LPMetadataProvider icon fetching.
    /// URL pattern: https://www.google.com/s2/favicons?domain=<host>&sz=64
    private func fetchFaviconFallback(for link: SavedLink, title: String?) {
        guard let host = link.rawURL.host else {
            updateLink(id: link.id, title: title, icon: nil)
            return
        }

        var components = URLComponents(string: "https://www.google.com/s2/favicons")
        components?.queryItems = [
            URLQueryItem(name: "domain", value: host),
            URLQueryItem(name: "sz", value: "64")   // 64pt — crisp on Retina
        ]

        guard let faviconURL = components?.url else {
            updateLink(id: link.id, title: title, icon: nil)
            return
        }

        URLSession.shared.dataTask(with: faviconURL) { [weak self] data, response, _ in
            guard let self else { return }

            // Google returns a 1×1 grey pixel for unknown domains —
            // treat small responses (< 200 bytes) as failures.
            var icon: NSImage?
            if let data, data.count > 200, let image = NSImage(data: data) {
                icon = image
            }

            self.updateLink(id: link.id, title: title, icon: icon)
        }.resume()
    }

    // MARK: - Public Actions

    func pin(id: UUID) {
        guard let index = links.firstIndex(where: { $0.id == id }) else { return }
        links[index].isPinned = true
        sortLinks()
        persist()
    }

    func unpin(id: UUID) {
        guard let index = links.firstIndex(where: { $0.id == id }) else { return }
        links[index].isPinned = false
        sortLinks()
        persist()
    }

    func remove(id: UUID) {
        links.removeAll { $0.id == id }
        persist()
    }

    func clearAll() {
        links.removeAll()
        searchResults = []
        store.deleteAll()
    }

    /// Sorts links: pinned first (preserving their relative pinned order),
    /// then unpinned sorted by capturedAt descending (newest first).
    /// This ensures unpinning a link restores it to its chronological position.
    private func sortLinks() {
        let pinned   = links.filter {  $0.isPinned }
        let unpinned = links.filter { !$0.isPinned }
            .sorted { $0.capturedAt > $1.capturedAt }
        links = pinned + unpinned
    }
}

// MARK: - URL Validation

// Internal so it can be unit tested without @testable import hacks.
extension URL {
    var isWebURL: Bool {
        guard let scheme = scheme?.lowercased() else { return false }
        return (scheme == "http" || scheme == "https") && !(host ?? "").isEmpty
    }
}
