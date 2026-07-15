import Foundation
import Observation

/// One recorded search: the query the user ran, when it ran, and a summary of
/// what came back. Persisted so history survives relaunches. Result items
/// themselves aren't serializable, so we store per-category counts plus a short
/// list of the top result labels rather than the `Song`/`Album` objects.
struct SearchHistoryEntry: Codable, Identifiable {
    let id: UUID
    var date: Date
    var query: String
    /// Whether the on-device model shaped these results.
    var usedIntelligence: Bool
    var counts: ResultCounts
    /// "Title — Subtitle" for the first few displayed results, for a readable
    /// at-a-glance sense of what the search returned.
    var topResults: [String]

    var resultCount: Int { counts.total }

    struct ResultCounts: Codable {
        var librarySongs = 0
        var libraryAlbums = 0
        var libraryArtists = 0
        var libraryPlaylists = 0
        var songs = 0
        var albums = 0
        var artists = 0
        var playlists = 0

        var total: Int {
            librarySongs + libraryAlbums + libraryArtists + libraryPlaylists
                + songs + albums + artists + playlists
        }
    }
}

/// Observable, UserDefaults-backed log of executed searches, newest first.
///
/// Searches run on a debounce as the user types, so a single intent produces a
/// burst of incremental queries ("b" → "be" → "bea" → "beat"). To keep the log
/// meaningful, a new entry that's a typing continuation of the most recent one
/// (a prefix in either direction, within a short window) replaces it rather than
/// appending — collapsing the burst down to the query the user settled on.
@Observable final class SearchHistoryStore {
    private(set) var entries: [SearchHistoryEntry]

    private static let key = "MiniMusic.searchHistory"
    private static let maxEntries = 200
    private static let coalesceWindow: TimeInterval = 12

    init() {
        entries = Self.load()
    }

    func record(
        query: String,
        usedIntelligence: Bool,
        counts: SearchHistoryEntry.ResultCounts,
        topResults: [String]
    ) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let entry = SearchHistoryEntry(
            id: UUID(),
            date: Date(),
            query: trimmed,
            usedIntelligence: usedIntelligence,
            counts: counts,
            topResults: topResults
        )

        if let last = entries.first,
           entry.date.timeIntervalSince(last.date) < Self.coalesceWindow,
           Self.isTypingContinuation(from: last.query, to: trimmed) {
            entries[0] = entry
        } else {
            entries.insert(entry, at: 0)
        }

        if entries.count > Self.maxEntries {
            entries.removeLast(entries.count - Self.maxEntries)
        }
        save()
    }

    func clear() {
        entries = []
        UserDefaults.standard.removeObject(forKey: Self.key)
    }

    // MARK: - Private

    /// True when `new` looks like continued typing of `old`: one is a
    /// case-insensitive prefix of the other and they aren't identical.
    private static func isTypingContinuation(from old: String, to new: String) -> Bool {
        guard old != new else { return true }
        let a = old.lowercased()
        let b = new.lowercased()
        return a.hasPrefix(b) || b.hasPrefix(a)
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        UserDefaults.standard.set(data, forKey: Self.key)
    }

    private static func load() -> [SearchHistoryEntry] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([SearchHistoryEntry].self, from: data)
        else { return [] }
        return decoded
    }
}
