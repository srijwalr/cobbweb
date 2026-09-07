// SemanticSearchEngine.swift
// On-device semantic search using Apple's NaturalLanguage framework.
//
// Design decisions:
// - Separate thresholds for sentence vs word embedding (different distance scales)
// - Field-weighted scoring: title > host > path > full URL
// - Stopword filtering so common words don't pollute word-embedding averages
// - Best-token-wins for word embedding (min not mean) to avoid weak-token drag
// - Lexical boost: partial word overlap adds a score bonus on top of semantic distance
// - Short tokens (2 chars) preserved for terms like "ai", "ui", "js", "go"

import Foundation
import NaturalLanguage

// MARK: - SearchResult

struct SearchResult {
    enum Category { case exact, related }
    let link: SavedLink
    let category: Category
    let distance: Double
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

            let lower        = trimmed.lowercased()
            let queryTokens  = self.tokenise(lower)

            var exactResults:   [SearchResult] = []
            var relatedResults: [(SearchResult, Double)] = []

            for link in links {
                // 1. Exact substring match — always shown first, distance 0.
                if self.lexicalMatch(query: lower, link: link) {
                    exactResults.append(SearchResult(link: link, category: .exact, distance: 0))
                    continue
                }

                // 2. Semantic scoring against individual fields (not one big blob).
                let distance = self.fieldWeightedScore(
                    queryTokens: queryTokens,
                    query: lower,
                    link: link
                )

                if distance <= self.effectiveThreshold {
                    relatedResults.append(
                        (SearchResult(link: link, category: .related, distance: distance), distance)
                    )
                }
            }

            let sorted = relatedResults.sorted { $0.1 < $1.1 }.map(\.0)
            DispatchQueue.main.async { completion(exactResults + sorted) }
        }
    }

    // MARK: - Lexical Match

    /// Checks all meaningful fields individually for substring presence.
    /// More precise than checking one concatenated blob.
    private func lexicalMatch(query: String, link: SavedLink) -> Bool {
        if let title = link.title, title.lowercased().contains(query) { return true }
        if let desc = link.pageDescription, desc.lowercased().contains(query) { return true }
        if link.host.lowercased().contains(query) { return true }
        if link.rawURL.absoluteString.lowercased().contains(query) { return true }
        return false
    }

    // MARK: - Field-Weighted Scoring

    /// Scores each field separately and combines with weights.
    /// Title is most important, then host, then path words, then full URL.
    /// This prevents URL boilerplate from diluting a strong title match.
    private func fieldWeightedScore(
        queryTokens: [String],
        query: String,
        link: SavedLink
    ) -> Double {
        struct Field { let text: String; let weight: Double }

        let pathWords = link.rawURL.pathComponents
            .joined(separator: " ")
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count >= 2 }
            .joined(separator: " ")

        let fields: [Field] = [
            Field(text: link.title ?? "",               weight: 1.0),
            Field(text: link.pageDescription ?? "",     weight: 0.9),
            Field(text: link.host,                      weight: 0.8),
            Field(text: pathWords,                      weight: 0.6),
            Field(text: link.rawURL.absoluteString,     weight: 0.2),
        ].filter { !$0.text.isEmpty }

        guard !fields.isEmpty else { return Self.maxDistance }

        var weightedSum   = 0.0
        var totalWeight   = 0.0

        for field in fields {
            let fieldScore = semanticScore(queryTokens: queryTokens,
                                           query: query,
                                           target: field.text.lowercased())
            // Apply lexical boost: if field contains any query token literally,
            // reduce distance by 20% to reward partial overlap.
            let boost = queryTokens.contains { field.text.lowercased().contains($0) } ? 0.8 : 1.0
            weightedSum += fieldScore * boost * field.weight
            totalWeight += field.weight
        }

        return weightedSum / totalWeight
    }

    // MARK: - Semantic Score (single field vs query)

    private func semanticScore(queryTokens: [String], query: String, target: String) -> Double {
        // Sentence embedding: compare full query string against field text.
        if let se = sentenceEmbedding {
            return se.distance(between: query, and: target)
        }

        // Word embedding: best-token-wins per query token (min not mean).
        // This means one strong-matching token can carry the result,
        // rather than weak tokens dragging the average up.
        if let we = wordEmbedding {
            let targetTokens = tokenise(target)
            guard !targetTokens.isEmpty, !queryTokens.isEmpty else { return Self.maxDistance }

            // For each query token, find its closest target token.
            let perQueryToken: [Double] = queryTokens.map { qt in
                targetTokens.map { we.distance(between: qt, and: $0) }.min() ?? Self.maxDistance
            }

            // Use the minimum across query tokens — best match wins.
            return perQueryToken.min() ?? Self.maxDistance
        }

        return Self.maxDistance
    }

    // MARK: - Effective Threshold

    /// Returns the appropriate threshold based on which model is loaded.
    private var effectiveThreshold: Double {
        if sentenceEmbedding != nil { return Self.sentenceThreshold }
        if wordEmbedding     != nil { return Self.wordThreshold }
        return 0 // no model → no semantic results
    }

    // MARK: - Tokenisation

    /// Splits text into lowercase tokens.
    /// Keeps tokens ≥ 2 chars (preserves "ai", "ui", "js", "go").
    /// Removes English stopwords that add noise to embeddings.
    private func tokenise(_ text: String) -> [String] {
        var tokens: [String] = []
        let tagger = NLTagger(tagSchemes: [.tokenType])
        tagger.string = text
        tagger.enumerateTags(in: text.startIndex..<text.endIndex,
                              unit: .word, scheme: .tokenType) { _, range in
            let word = String(text[range]).lowercased()
            if word.count >= 2, !Self.stopwords.contains(word) {
                tokens.append(word)
            }
            return true
        }
        if tokens.isEmpty {
            tokens = text
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { $0.count >= 2 && !Self.stopwords.contains($0.lowercased()) }
        }
        return tokens
    }
}
