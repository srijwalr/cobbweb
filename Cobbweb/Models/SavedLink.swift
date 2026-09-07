// SavedLink.swift
import Foundation
import AppKit

struct SavedLink: Identifiable, Equatable {

    let id: UUID
    let rawURL: URL
    let capturedAt: Date

    var title: String?
    var pageDescription: String?
    var isPinned: Bool = false

    /// Not persisted — re-fetched on launch.
    var iconImage: NSImage?

    var host: String {
        rawURL.host ?? rawURL.absoluteString
    }

    var searchableProfile: String {
        // Extract readable words from the URL path by splitting on non-alphanumeric chars.
        // e.g. "/chicken-tikka-masala" → "chicken tikka masala"
        let pathWords = rawURL.pathComponents
            .joined(separator: " ")
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count > 2 }
            .joined(separator: " ")

        return [title ?? "", pageDescription ?? "", host, pathWords, rawURL.absoluteString]
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    init(url: URL) {
        self.id = UUID()
        self.rawURL = url
        self.capturedAt = Date()
    }

    static func == (lhs: SavedLink, rhs: SavedLink) -> Bool {
        lhs.id == rhs.id &&
        lhs.title == rhs.title &&
        lhs.pageDescription == rhs.pageDescription &&
        lhs.isPinned == rhs.isPinned &&
        lhs.iconImage === rhs.iconImage
    }
}

// MARK: - Codable DTO

struct SavedLinkRecord: Codable {
    let id: UUID
    let rawURL: URL
    let capturedAt: Date
    let title: String?
    let pageDescription: String?
    let isPinned: Bool

    // Default isPinned to false and pageDescription to nil so old persisted records
    // without these fields decode cleanly (CodingKeys + init(from:) handles this).
    init(id: UUID, rawURL: URL, capturedAt: Date, title: String?, pageDescription: String? = nil, isPinned: Bool = false) {
        self.id = id
        self.rawURL = rawURL
        self.capturedAt = capturedAt
        self.title = title
        self.pageDescription = pageDescription
        self.isPinned = isPinned
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id              = try container.decode(UUID.self,   forKey: .id)
        rawURL          = try container.decode(URL.self,    forKey: .rawURL)
        capturedAt      = try container.decode(Date.self,   forKey: .capturedAt)
        title           = try container.decodeIfPresent(String.self, forKey: .title)
        // Gracefully default to nil for records saved before this field existed.
        pageDescription = try? container.decodeIfPresent(String.self, forKey: .pageDescription) ?? nil
        // Gracefully default to false for records saved before this field existed.
        isPinned        = (try? container.decodeIfPresent(Bool.self, forKey: .isPinned)) ?? false
    }
}

extension SavedLink {
    var record: SavedLinkRecord {
        SavedLinkRecord(id: id, rawURL: rawURL, capturedAt: capturedAt,
                        title: title, pageDescription: pageDescription, isPinned: isPinned)
    }

    init(record: SavedLinkRecord) {
        self.id              = record.id
        self.rawURL          = record.rawURL
        self.capturedAt      = record.capturedAt
        self.title           = record.title
        self.pageDescription = record.pageDescription
        self.isPinned        = record.isPinned
        self.iconImage       = nil
    }
}
