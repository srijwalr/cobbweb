import XCTest
@testable import Cobbweb

final class LinkStoreTests: XCTestCase {

    private var tempDir: URL!
    private var store: TestLinkStore!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        store = TestLinkStore(directory: tempDir)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    // MARK: - Load

    func test_load_returnsEmpty_whenNoFile() {
        XCTAssertTrue(store.load().isEmpty)
    }

    func test_load_returnsEmpty_whenFileCorrupt() throws {
        try "not valid json".write(to: tempDir.appendingPathComponent("links.json"),
                                   atomically: true, encoding: .utf8)
        XCTAssertTrue(store.load().isEmpty)
    }

    // MARK: - Save & Load

    func test_saveAndLoad_roundTrip() throws {
        let record = makeRecord(urlString: "https://apple.com", title: "Apple")
        store.save([record])
        flush()
        let loaded = store.load()
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded.first?.title, "Apple")
        XCTAssertEqual(loaded.first?.rawURL.absoluteString, "https://apple.com")
    }

    func test_save_multiple() throws {
        store.save([
            makeRecord(urlString: "https://a.com", title: "A"),
            makeRecord(urlString: "https://b.com", title: "B"),
            makeRecord(urlString: "https://c.com", title: nil),
        ])
        flush()
        XCTAssertEqual(store.load().count, 3)
    }

    func test_save_overwritesPrevious() throws {
        store.save([makeRecord(urlString: "https://first.com", title: "First")])
        store.save([makeRecord(urlString: "https://second.com", title: "Second")])
        flush()
        let loaded = store.load()
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded.first?.rawURL.absoluteString, "https://second.com")
    }

    // MARK: - Delete

    func test_deleteAll_removesFile() throws {
        store.save([makeRecord(urlString: "https://example.com", title: nil)])
        flush()
        store.deleteAll()
        flush()
        XCTAssertTrue(store.load().isEmpty)
    }

    // MARK: - File Permissions

    func test_filePermissions_are600() throws {
        store.save([makeRecord(urlString: "https://secure.com", title: nil)])
        flush()
        let attrs = try FileManager.default.attributesOfItem(
            atPath: tempDir.appendingPathComponent("links.json").path)
        XCTAssertEqual(attrs[.posixPermissions] as? Int, 0o600)
    }

    // MARK: - isPinned persistence

    func test_isPinned_persists() throws {
        let record = makeRecord(urlString: "https://pinned.com", title: "Pinned", isPinned: true)
        store.save([record])
        flush()
        XCTAssertTrue(store.load().first?.isPinned == true)
    }

    // MARK: - Helpers

    private func flush() {
        let exp = expectation(description: "queue flush")
        store.queue.async { exp.fulfill() }
        wait(for: [exp], timeout: 2)
    }

    private func makeRecord(urlString: String, title: String?,
                             isPinned: Bool = false) -> SavedLinkRecord {
        SavedLinkRecord(id: UUID(), rawURL: URL(string: urlString)!,
                        capturedAt: Date(), title: title, isPinned: isPinned)
    }
}

// MARK: - Testable Store

final class TestLinkStore: LinkStoring {

    let queue = DispatchQueue(label: "com.cobbweb.store.test", qos: .utility)
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let storeURL: URL

    init(directory: URL) {
        self.storeURL = directory.appendingPathComponent("links.json")
        encoder.outputFormatting = .prettyPrinted
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    func load() -> [SavedLinkRecord] {
        guard FileManager.default.fileExists(atPath: storeURL.path) else { return [] }
        guard let data = try? Data(contentsOf: storeURL) else { return [] }
        return (try? decoder.decode([SavedLinkRecord].self, from: data)) ?? []
    }

    func save(_ records: [SavedLinkRecord]) {
        queue.async { [weak self] in
            guard let self, let data = try? self.encoder.encode(records) else { return }
            try? data.write(to: self.storeURL, options: .atomic)
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o600], ofItemAtPath: self.storeURL.path)
        }
    }

    func deleteAll() {
        queue.async { [weak self] in
            guard let self else { return }
            try? FileManager.default.removeItem(at: self.storeURL)
        }
    }
}
