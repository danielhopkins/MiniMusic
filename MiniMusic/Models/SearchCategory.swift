import Foundation

/// A kind of Apple Music search result. Used to scope a query to specific
/// result types (e.g. "piano playlist" → `.playlist`).
enum SearchCategory: String, CaseIterable {
    case song, album, artist, playlist

    /// Keyword → category, covering singular, plural and common synonyms. Used
    /// to detect an explicit type filter typed at the start or end of a query.
    static let keywords: [String: SearchCategory] = [
        "song": .song, "songs": .song, "track": .song, "tracks": .song,
        "album": .album, "albums": .album,
        "artist": .artist, "artists": .artist, "band": .artist, "bands": .artist,
        "playlist": .playlist, "playlists": .playlist,
    ]
}
