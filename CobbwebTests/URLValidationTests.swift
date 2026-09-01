import XCTest
@testable import Cobbweb

final class URLValidationTests: XCTestCase {

    func test_https_valid()          { XCTAssertTrue(URL(string: "https://github.com")!.isWebURL) }
    func test_http_valid()           { XCTAssertTrue(URL(string: "http://example.com")!.isWebURL) }
    func test_withPath_valid()       { XCTAssertTrue(URL(string: "https://github.com/apple/swift")!.isWebURL) }
    func test_withQuery_valid()      { XCTAssertTrue(URL(string: "https://example.com/s?q=hello")!.isWebURL) }
    func test_withPort_valid()       { XCTAssertTrue(URL(string: "https://localhost:8080")!.isWebURL) }
    func test_ipAddress_valid()      { XCTAssertTrue(URL(string: "https://192.168.1.1")!.isWebURL) }
    func test_subdomain_valid()      { XCTAssertTrue(URL(string: "https://news.ycombinator.com")!.isWebURL) }
    func test_uppercaseScheme_valid(){ XCTAssertTrue(URL(string: "HTTPS://example.com")!.isWebURL) }

    func test_ftp_invalid()    { XCTAssertFalse(URL(string: "ftp://files.example.com")!.isWebURL) }
    func test_mailto_invalid() { XCTAssertFalse(URL(string: "mailto:user@example.com")!.isWebURL) }
    func test_file_invalid()   { XCTAssertFalse(URL(string: "file:///Users/test/doc.pdf")!.isWebURL) }

    func test_emptyHost_invalid() {
        if let url = URL(string: "https://") { XCTAssertFalse(url.isWebURL) }
    }

    func test_noScheme_invalid() {
        if let url = URL(string: "github.com") { XCTAssertFalse(url.isWebURL) }
    }
}
