// LinkStore.swift
// Lightweight persistence layer for SavedLink records.
//
// Storage location: ~/Library/Application Support/Cobbweb/links.json
// File permissions: 0600 (owner read/write only).
// All I/O runs on a dedicated background serial queue.

import Foundation

// MARK: - Protocol (enables mocking in tests)

protocol LinkStoring {
    func load() -> [SavedLinkRecord]
    func save(_ records: [SavedLinkRecord])
    func deleteAll()
}

// MARK: - Production Implementation

final class LinkStore: LinkStoring {

    static let shared = LinkStore()

    private let queue = DispatchQueue(label: "com.cobbweb.store", qos: .utility)
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private var storeURL: URL = {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        let dir = appSupport.appendingPathComponent("Cobbweb", isDirectory: true)
        try? FileManager.default.createDirectory(
            at: dir,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        return dir.appendingPathComponent("links.json")
    }()

    private init() {
        encoder.outputFormatting = .prettyPrinted
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    func load() -> [SavedLinkRecord] {
        guard FileManager.default.fileExists(atPath: storeURL.path) else { return [] }
        do {
            let data = try Data(contentsOf: storeURL)
            return try decoder.decode([SavedLinkRecord].self, from: data)
        } catch {
            print("[Cobbweb] Store load error: \(error.localizedDescription)")
            return []
        }
    }

    func save(_ records: [SavedLinkRecord]) {
        queue.async { [weak self] in
            guard let self else { return }
            do {
                let data = try self.encoder.encode(records)
                try data.write(to: self.storeURL, options: .atomic)
                try FileManager.default.setAttributes(
                    [.posixPermissions: 0o600],
                    ofItemAtPath: self.storeURL.path
                )
            } catch {
                print("[Cobbweb] Store save error: \(error.localizedDescription)")
            }
        }
    }

    func deleteAll() {
        queue.async { [weak self] in
            guard let self else { return }
            try? FileManager.default.removeItem(at: self.storeURL)
        }
    }
}

// MARK: - In-Memory Mock (used in unit tests)

final class MockLinkStore: LinkStoring {
    private(set) var savedRecords: [SavedLinkRecord] = []
    var preloadedRecords: [SavedLinkRecord] = []
    private(set) var deleteAllCalled = false

    func load() -> [SavedLinkRecord] { preloadedRecords }
    func save(_ records: [SavedLinkRecord]) { savedRecords = records }
    func deleteAll() { savedRecords = []; deleteAllCalled = true }
}
