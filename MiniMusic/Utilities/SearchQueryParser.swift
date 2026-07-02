import Foundation

/// Deterministic, instant parser that pulls an explicit category filter out of a
/// search query. It recognises a type keyword at the **start or end** of the
/// query and strips it, so "piano playlist", "playlists piano" and "swift artist"
/// scope to a single kind of result.
///
/// This is the always-available baseline; `SearchIntentParser` refines it with
/// the on-device model when Apple Intelligence is present.
enum SearchQueryParser {
    /// Returns the cleaned search term and any category the query scoped to. An
    /// empty `categories` array means "search everything".
    static func parse(_ raw: String) -> (term: String, categories: [SearchCategory]) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        var tokens = trimmed.split(whereSeparator: { $0.isWhitespace }).map(String.init)

        // Need at least two tokens: a bare type word ("playlist") stays a normal
        // all-category search rather than an empty-term filter.
        guard tokens.count > 1 else { return (trimmed, []) }

        var categories: [SearchCategory] = []
        if let category = SearchCategory.keywords[tokens[tokens.count - 1].lowercased()] {
            categories = [category]
            tokens.removeLast()
        } else if let category = SearchCategory.keywords[tokens[0].lowercased()] {
            categories = [category]
            tokens.removeFirst()
        }

        let term = tokens.joined(separator: " ")
        return (term.isEmpty ? trimmed : term, categories)
    }
}
