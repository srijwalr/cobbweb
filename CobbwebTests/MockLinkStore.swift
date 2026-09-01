import Foundation
@testable import Cobbweb

/// In-memory mock of LinkStoring used by ClipboardMonitorTests.
final class MockLinkStore: LinkStoring {
    private(set) var savedRecords: [SavedLinkRecord] = []
    var preloadedRecords: [SavedLinkRecord] = []
    private(set) var deleteAllCalled = false

    func load() -> [SavedLinkRecord] { preloadedRecords }
    func save(_ records: [SavedLinkRecord]) { savedRecords = records }
    func deleteAll() { savedRecords = []; deleteAllCalled = true }
}
