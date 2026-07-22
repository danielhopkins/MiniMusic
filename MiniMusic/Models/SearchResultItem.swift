import MusicKit

enum SearchResultItem: Identifiable, Equatable {
    case librarySong(Song)
    case libraryAlbum(Album)
    case libraryArtist(Artist)
    case libraryPlaylist(Playlist)
    case catalogSong(Song)
    case catalogAlbum(Album)
    case catalogArtist(Artist)
    case catalogPlaylist(Playlist)
    case catalogStation(Station)

    var id: String {
        switch self {
        case .librarySong(let s): return "lib-song-\(s.id)"
        case .libraryAlbum(let a): return "lib-album-\(a.id)"
        case .libraryArtist(let a): return "lib-artist-\(a.id)"
        case .libraryPlaylist(let p): return "lib-playlist-\(p.id)"
        case .catalogSong(let s): return "cat-song-\(s.id)"
        case .catalogAlbum(let a): return "cat-album-\(a.id)"
        case .catalogArtist(let a): return "cat-artist-\(a.id)"
        case .catalogPlaylist(let p): return "cat-playlist-\(p.id)"
        case .catalogStation(let s): return "cat-station-\(s.id)"
        }
    }

    var title: String {
        switch self {
        case .librarySong(let s), .catalogSong(let s): return s.title
        case .libraryAlbum(let a), .catalogAlbum(let a): return a.title
        case .libraryArtist(let a), .catalogArtist(let a): return a.name
        case .libraryPlaylist(let p), .catalogPlaylist(let p): return p.name
        case .catalogStation(let s): return s.name
        }
    }

    var subtitle: String {
        switch self {
        case .librarySong(let s), .catalogSong(let s): return s.artistName
        case .libraryAlbum(let a), .catalogAlbum(let a): return a.artistName
        case .libraryArtist, .catalogArtist: return "Artist"
        case .libraryPlaylist(let p), .catalogPlaylist(let p): return p.curatorName ?? "Apple Music"
        case .catalogStation(let s): return s.stationProviderName ?? (s.isLive ? "Live Radio" : "Station")
        }
    }

    var artwork: Artwork? {
        switch self {
        case .librarySong(let s), .catalogSong(let s): return s.artwork
        case .libraryAlbum(let a), .catalogAlbum(let a): return a.artwork
        case .libraryArtist(let a), .catalogArtist(let a): return a.artwork
        case .libraryPlaylist(let p), .catalogPlaylist(let p): return p.artwork
        case .catalogStation(let s): return s.artwork
        }
    }

    var sectionName: String {
        switch self {
        case .librarySong: return "Library Songs"
        case .libraryAlbum: return "Library Albums"
        case .libraryArtist: return "Library Artists"
        case .libraryPlaylist: return "Library Playlists"
        case .catalogSong: return "Songs"
        case .catalogAlbum: return "Albums"
        case .catalogArtist: return "Artists"
        case .catalogPlaylist: return "Playlists"
        case .catalogStation: return "Radio Stations"
        }
    }

    var isLibrary: Bool {
        switch self {
        case .librarySong, .libraryAlbum, .libraryArtist, .libraryPlaylist: return true
        case .catalogSong, .catalogAlbum, .catalogArtist, .catalogPlaylist, .catalogStation:
            return false
        }
    }

    var isArtist: Bool {
        switch self {
        case .libraryArtist, .catalogArtist: return true
        default: return false
        }
    }

    /// Whether "Add to Library" and "Favorite" apply. Artists aren't library
    /// items, and stations can't be added or rated — mirroring
    /// `PlaybackSource.supportsLibraryActions` for the now-playing source.
    var supportsLibraryActions: Bool {
        switch self {
        case .libraryArtist, .catalogArtist, .catalogStation: return false
        default: return true
        }
    }

    static func == (lhs: SearchResultItem, rhs: SearchResultItem) -> Bool {
        lhs.id == rhs.id
    }
}
