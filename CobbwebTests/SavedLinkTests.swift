import XCTest
@testable import Cobbweb

final class SavedLinkTests: XCTestCase {

    func test_init_setsURL() {
        let url = URL(string: "https://github.com")!
        let link = SavedLink(url: url)
        XCTAssertEqual(link.rawURL, url)
    }

    func test_init_generatesUniqueIDs() {
        let url = URL(string: "https://github.com")!
        XCTAssertNotEqual(SavedLink(url: url).id, SavedLink(url: url).id)
    }

    func test_init_titleAndIconNilByDefault() {
        let link = SavedLink(url: URL(string: "https://example.com")!)
        XCTAssertNil(link.title)
        XCTAssertNil(link.iconImage)
    }

    func test_init_isPinnedFalseByDefault() {
        let link = SavedLink(url: URL(string: "https://example.com")!)
        XCTAssertFalse(link.isPinned)
    }

    func test_host_returnsHostComponent() {
        let link = SavedLink(url: URL(string: "https://www.github.com/apple/swift")!)
        XCTAssertEqual(link.host, "www.github.com")
    }

    func test_searchableProfile_includesTitle() {
        var link = SavedLink(url: URL(string: "https://example.com/my-page")!)
        link.title = "My Page Title"
        XCTAssertTrue(link.searchableProfile.contains("My Page Title"))
    }

    func test_searchableProfile_includesPathWords() {
        let link = SavedLink(url: URL(string: "https://food.com/chicken-tikka-masala")!)
        let profile = link.searchableProfile
        XCTAssertTrue(profile.contains("chicken"))
        XCTAssertTrue(profile.contains("tikka"))
        XCTAssertTrue(profile.contains("masala"))
    }

    func test_codableRoundTrip() throws {
        var link = SavedLink(url: URL(string: "https://apple.com")!)
        link.title = "Apple"
        link.isPinned = true

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(link.record)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(SavedLinkRecord.self, from: data)

        XCTAssertEqual(decoded.id, link.id)
        XCTAssertEqual(decoded.title, "Apple")
        XCTAssertTrue(decoded.isPinned)
    }

    func test_initFromRecord_restoresFields() {
        let record = SavedLinkRecord(
            id: UUID(),
            rawURL: URL(string: "https://swift.org")!,
            capturedAt: Date(),
            title: "Swift",
            isPinned: true
        )
        let link = SavedLink(record: record)
        XCTAssertEqual(link.title, "Swift")
        XCTAssertTrue(link.isPinned)
        XCTAssertNil(link.iconImage)
    }

    func test_recordDecodesOldFormat_withoutIsPinned() throws {
        // Old records without isPinned should default to false.
        let json = """
        {"id":"00000000-0000-0000-0000-000000000001",
         "rawURL":"https://example.com",
         "capturedAt":"2026-01-01T00:00:00Z",
         "title":null}
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let record = try decoder.decode(SavedLinkRecord.self, from: json.data(using: .utf8)!)
        XCTAssertFalse(record.isPinned)
    }
}
