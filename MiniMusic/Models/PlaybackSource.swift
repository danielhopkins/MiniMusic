import MusicKit

/// The container the current queue was started from — an album, playlist, or
/// station. Tracked so the player can show "Playing from …" alongside the queue
/// and let the user act on the source (add it to their library, favorite it)
/// without having to hunt for it again in search.
///
/// The `isLibrary` flag records whether the item came from the user's library
/// rather than the catalog, which decides both whether "Add to Library" applies
/// and which ratings endpoint a favorite hits.
enum PlaybackSource: Equatable {
    case album(Album, isLibrary: Bool)
    case playlist(Playlist, isLibrary: Bool)
    case station(Station)

    var title: String {
        switch self {
        case .album(let album, _): return album.title
        case .playlist(let playlist, _): return playlist.name
        case .station(let station): return station.name
        }
    }

    var subtitle: String {
        switch self {
        case .album(let album, _): return album.artistName
        case .playlist(let playlist, _): return playlist.curatorName ?? "Playlist"
        case .station: return "Station"
        }
    }

    /// Short noun for the kind of source, shown as "Playing from {kindLabel}".
    var kindLabel: String {
        switch self {
        case .album: return "Album"
        case .playlist: return "Playlist"
        case .station: return "Station"
        }
    }

    var artwork: Artwork? {
        switch self {
        case .album(let album, _): return album.artwork
        case .playlist(let playlist, _): return playlist.artwork
        case .station(let station): return station.artwork
        }
    }

    /// Library playlists carry a composited "four-up" artwork that MusicKit
    /// won't render at an arbitrary size (Apple builds that mosaic on the fly),
    /// so they display as blank. Albums and catalog playlists carry a single
    /// real cover that renders fine. This picks the artwork to show, falling
    /// back to the currently-playing track's cover when the source's own
    /// artwork can't be trusted to render.
    func displayArtwork(nowPlaying: Artwork?) -> Artwork? {
        if case .playlist(_, let isLibrary) = self, isLibrary {
            return nowPlaying ?? artwork
        }
        return artwork ?? nowPlaying
    }

    /// Whether the source is already in the user's library (so "Add to Library"
    /// should read as already-added rather than an available action).
    var isInLibrary: Bool {
        switch self {
        case .album(_, let isLibrary), .playlist(_, let isLibrary): return isLibrary
        case .station: return false
        }
    }

    /// Stations can't be added to the library or rated, so they show no actions.
    var supportsLibraryActions: Bool {
        switch self {
        case .album, .playlist: return true
        case .station: return false
        }
    }
}
