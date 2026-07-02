import Foundation

/// The framework-free facets a query resolves to. Produced by the on-device
/// model (`SearchIntent.facets`) or, in the fallback path, from the deterministic
/// `SearchQueryParser`. Kept plain so the planner is fully unit-testable.
struct SearchFacets: Equatable {
    var term: String
    var artist: String
    var album: String
    var song: String
    /// Mood/vibe words ("exciting", "relaxing") that lexical search can't honor;
    /// used to re-rank results after fetching, not to route the search.
    var descriptor: String
    var categories: [SearchCategory]

    nonisolated init(term: String, artist: String = "", album: String = "", song: String = "",
                     descriptor: String = "", categories: [SearchCategory] = []) {
        self.term = term
        self.artist = artist
        self.album = album
        self.song = song
        self.descriptor = descriptor
        self.categories = categories
    }
}

/// How a search should actually be executed, chosen from the facets. This is
/// what makes the search "dynamic": the *shape* of the MusicKit work changes with
/// what the user asked for.
enum SearchStrategy: Equatable {
    /// Resolve an album, then list its tracks (e.g. "songs from the Red album").
    case albumTracks(album: String, artist: String)
    /// Resolve an artist, then list their top songs (e.g. "Taylor Swift songs").
    case artistTopSongs(artist: String)
    /// Plain free-text search across the requested categories (the default).
    case text(term: String, categories: [SearchCategory])
}

extension SearchFacets {
    /// Facets derived purely from the deterministic keyword parser — the fallback
    /// used when the on-device model is unavailable. Only `term` and `categories`
    /// are populated (no artist/album/song facets), so the planner always routes
    /// these to a plain text search.
    init(deterministicallyParsing query: String) {
        let parsed = SearchQueryParser.parse(query)
        self.init(term: parsed.term, categories: parsed.categories)
    }
}

/// Turns facets into a concrete execution strategy. Pure and deterministic, so
/// the routing decisions can be unit-tested without MusicKit or the model.
enum SearchPlanner {
    static func plan(_ facets: SearchFacets) -> SearchStrategy {
        // A named album with no specific song → list that album's tracks.
        if !facets.album.isEmpty, facets.song.isEmpty {
            return .albumTracks(album: facets.album, artist: facets.artist)
        }
        // A named artist, wanting songs, with no specific song → their top songs.
        if !facets.artist.isEmpty, facets.song.isEmpty, facets.categories == [.song] {
            return .artistTopSongs(artist: facets.artist)
        }
        // Everything else is a normal text search.
        return .text(term: facets.term, categories: facets.categories)
    }
}
