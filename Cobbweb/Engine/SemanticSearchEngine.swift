// SemanticSearchEngine.swift
// On-device semantic search using Apple's NaturalLanguage framework.
//
// Design decisions:
// - Separate thresholds for sentence vs word embedding (different distance scales)
// - Field-weighted scoring: title > description > host > path > full URL
// - Stopword filtering so common words don't pollute word-embedding averages
// - Best-token-wins for word embedding (min not mean) to avoid weak-token drag
// - Lexical boost: partial word overlap adds a score bonus on top of semantic distance
// - Short tokens (2 chars) preserved for terms like "ai", "ui", "js", "go"
// - Per-link fields are pre-lowercased and tokenised once per search call,
//   not re-computed for every field × every embedding distance call

import Foundation
import NaturalLanguage

// MARK: - SearchResult

struct SearchResult {
    enum Category { case exact, related }
    let link: SavedLink
    let category: Category
    let distance: Double
}

// MARK: - Prepared link (computed once per search call)

private struct PreparedLink {
    let link: SavedLink

    struct Field {
        let text: String        // lowercased
        let tokens: [String]    // pre-tokenised
        let weight: Double
    }

    let fields: [Field]

    /// Flat lowercased string across all fields for lexical match.
    let lexicalBlob: String
}

// MARK: - Engine

final class SemanticSearchEngine {

    // Separate thresholds — sentence and word embeddings produce distances
    // on different scales so they need different cutoffs.
    private static let sentenceThreshold: Double = 0.85
    private static let wordThreshold: Double     = 0.65

    static let maxDistance: Double = 2.0

    private let sentenceEmbedding: NLEmbedding?
    private let wordEmbedding: NLEmbedding?
    private let queue = DispatchQueue(label: "com.cobbweb.semantic", qos: .userInitiated)

    // English stopwords that add noise to word-embedding averages.
    private static let stopwords: Set<String> = [
        "the", "and", "for", "are", "but", "not", "you", "all",
        "can", "had", "her", "was", "one", "our", "out", "day",
        "get", "has", "him", "his", "how", "its", "may", "now",
        "use", "way", "who", "did", "let", "put", "say", "she",
        "too", "www", "com", "http", "https"
    ]

    init() {
        sentenceEmbedding = NLEmbedding.sentenceEmbedding(for: .english)
        wordEmbedding     = NLEmbedding.wordEmbedding(for: .english)

        if sentenceEmbedding != nil {
            print("[Cobbweb] Sentence embedding loaded ✓")
        } else if wordEmbedding != nil {
            print("[Cobbweb] Word embedding loaded ✓ (sentence embedding unavailable)")
        } else {
            print("[Cobbweb] No embedding model — substring search only")
        }
    }

    // MARK: - Public Search

    func search(
        query: String,
        in links: [SavedLink],
        completion: @escaping ([SearchResult]) -> Void
    ) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmed.isEmpty else {
            let all = links.map { SearchResult(link: $0, category: .exact, distance: 0) }
            DispatchQueue.main.async { completion(all) }
            return
        }

        queue.async { [weak self] in
            guard let self else { return }

            let lower       = trimmed.lowercased()
            let queryTokens = Self.fastTokenise(lower)

            // Pre-process all links once — lowercased fields + tokens computed here,
            // not repeated inside the per-field scoring loop.
            let prepared = links.map { Self.prepare($0) }

            var exactResults:   [SearchResult] = []
            var relatedResults: [(SearchResult, Double)] = []

            for p in prepared {
                // 1. Fast lexical match against pre-built blob.
                if p.lexicalBlob.contains(lower) {
                    exactResults.append(SearchResult(link: p.link, category: .exact, distance: 0))
                    continue
                }

                // 2. Semantic scoring using pre-computed fields.
                let distance = self.fieldWeightedScore(queryTokens: queryTokens,
                                                       query: lower,
                                                       prepared: p)

                if distance <= self.effectiveThreshold {
                    relatedResults.append(
                        (SearchResult(link: p.link, category: .related, distance: distance), distance)
                    )
                }
            }

            let sorted = relatedResults.sorted { $0.1 < $1.1 }.map(\.0)
            DispatchQueue.main.async { completion(exactResults + sorted) }
        }
    }

    // MARK: - Preparation

    /// Pre-lowercases and tokenises all fields for a link.
    /// Called once per link per search — results used for both lexical and semantic paths.
    private static func prepare(_ link: SavedLink) -> PreparedLink {
        let pathWords = link.rawURL.pathComponents
            .joined(separator: " ")
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count >= 2 }
            .joined(separator: " ")

        let rawFields: [(String, Double)] = [
            (link.title ?? "",              1.0),
            (link.pageDescription ?? "",   0.9),
            (link.host,                    0.8),
            (pathWords,                    0.6),
            (link.rawURL.absoluteString,   0.2),
        ].filter { !$0.0.isEmpty }

        let fields = rawFields.map { text, weight -> PreparedLink.Field in
            let lower = text.lowercased()
            return PreparedLink.Field(text: lower, tokens: Self.fastTokenise(lower), weight: weight)
        }

        // Lexical blob: space-joined lowercased field texts for a single .contains check.
        let blob = fields.map(\.text).joined(separator: " ")

        return PreparedLink(link: link, fields: fields, lexicalBlob: blob)
    }

    // MARK: - Field-Weighted Scoring

    private func fieldWeightedScore(
        queryTokens: [String],
        query: String,
        prepared: PreparedLink
    ) -> Double {
        guard !prepared.fields.isEmpty else { return Self.maxDistance }

        var weightedSum = 0.0
        var totalWeight = 0.0

        for field in prepared.fields {
            let fieldScore = semanticScore(queryTokens: queryTokens,
                                           query: query,
                                           targetTokens: field.tokens,
                                           target: field.text)
            // Lexical boost: field already lowercased, no extra allocation needed.
            let boost = queryTokens.contains { field.text.contains($0) } ? 0.8 : 1.0
            weightedSum += fieldScore * boost * field.weight
            totalWeight += field.weight
        }

        return weightedSum / totalWeight
    }

    // MARK: - Semantic Score (single field vs query)

    private func semanticScore(
        queryTokens: [String],
        query: String,
        targetTokens: [String],
        target: String
    ) -> Double {
        // Sentence embedding: single distance call per field.
        if let se = sentenceEmbedding {
            return se.distance(between: query, and: target)
        }

        // Word embedding: best-token-wins per query token.
        if let we = wordEmbedding {
            guard !targetTokens.isEmpty, !queryTokens.isEmpty else { return Self.maxDistance }

            let perQueryToken: [Double] = queryTokens.map { qt in
                targetTokens.map { we.distance(between: qt, and: $0) }.min() ?? Self.maxDistance
            }
            return perQueryToken.min() ?? Self.maxDistance
        }

        return Self.maxDistance
    }

    // MARK: - Effective Threshold

    private var effectiveThreshold: Double {
        if sentenceEmbedding != nil { return Self.sentenceThreshold }
        if wordEmbedding     != nil { return Self.wordThreshold }
        return 0
    }

    // MARK: - Tokenisation

    /// Fast tokeniser using character splitting — avoids NLTagger overhead during search.
    /// NLTagger is accurate but slow to instantiate; for search-time tokenisation the
    /// simple split is indistinguishable in quality for short field text.
    static func fastTokenise(_ text: String) -> [String] {
        text.components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count >= 2 && !stopwords.contains($0) }
    }
}
