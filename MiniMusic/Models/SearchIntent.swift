import FoundationModels

/// Structured result of parsing a search query with the on-device model. Marked
/// `@Generable` so Foundation Models fills it via guided generation. The facets
/// (`artist`, `album`, `song`) let `SearchPlanner` choose *how* to search, not
/// just what text to match.
@Generable
struct SearchIntent {
    @Guide(description: "A clean, spelling-corrected search string for the core subject only — genre, artist, album, or song — WITHOUT any mood or vibe adjectives (those go in `descriptor`). Fix misspellings ('tailor swift' → 'Taylor Swift'); drop filler like 'from', 'the', 'by'. E.g. 'exciting classical playlists' → 'classical'; 'tailor swift songs from the red album' → 'Taylor Swift Red'.")
    var term: String

    @Guide(description: "Mood, vibe, energy, or descriptive adjectives the user wants (e.g. 'exciting', 'relaxing', 'upbeat', 'sad'), kept separate from the subject. Empty if the query names no mood.")
    var descriptor: String

    @Guide(description: "The artist or band name if the user named one, corrected for spelling. Empty if no artist was named.")
    var artist: String

    @Guide(description: "The album name if the user named a specific album — OR the soundtrack/cast album of a named movie, TV show, or musical (e.g. 'songs from the Matilda Netflix musical' → 'Matilda the Musical Netflix Soundtrack'). Keep distinguishing words like the platform, film, or year so the right version is found. Empty if no album or production was named.")
    var album: String

    @Guide(description: "A specific song/track title if the user named one. Empty if the user did not ask for one particular song.")
    var song: String

    @Guide(description: "The kinds of results the user clearly asked for. Leave empty when the query names no type, so all kinds are searched.")
    var categories: [GenerableCategory]

    /// The intent projected onto the framework-free `SearchFacets` the planner
    /// consumes.
    var facets: SearchFacets {
        SearchFacets(
            term: term,
            artist: artist,
            album: album,
            song: song,
            descriptor: descriptor,
            categories: categories.map(\.searchCategory)
        )
    }
}

/// Category choices exposed to the model. Kept separate from `SearchCategory` so
/// that type (and the deterministic parser/planner/tests) stay free of the
/// FoundationModels import.
@Generable
enum GenerableCategory {
    case song, album, artist, playlist

    var searchCategory: SearchCategory {
        switch self {
        case .song: .song
        case .album: .album
        case .artist: .artist
        case .playlist: .playlist
        }
    }
}
