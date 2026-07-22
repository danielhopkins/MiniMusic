import Foundation

/// A kind of Apple Music search result. Used to scope a query to specific
/// result types (e.g. "piano playlist" → `.playlist`).
enum SearchCategory: String, CaseIterable {
    case song, album, artist, playlist, station

    /// Keyword → category, covering singular, plural and common synonyms. Used
    /// to detect an explicit type filter typed at the start or end of a query.
    ///
    /// Stripping the radio/station keyword matters more here than for the other
    /// categories: Apple's station search appears to require every token to
    /// appear in the station's name, and no station is actually *named* "radio".
    /// "cpr radio" returns nothing while "cpr" returns both CPR streams, so the
    /// keyword has to come off before the search runs.
    static let keywords: [String: SearchCategory] = [
        "song": .song, "songs": .song, "track": .song, "tracks": .song,
        "album": .album, "albums": .album,
        "artist": .artist, "artists": .artist, "band": .artist, "bands": .artist,
        "playlist": .playlist, "playlists": .playlist,
        "radio": .station, "station": .station, "stations": .station,
    ]
}
