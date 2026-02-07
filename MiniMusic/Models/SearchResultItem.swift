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
        }
    }

    var title: String {
        switch self {
        case .librarySong(let s), .catalogSong(let s): return s.title
        case .libraryAlbum(let a), .catalogAlbum(let a): return a.title
        case .libraryArtist(let a), .catalogArtist(let a): return a.name
        case .libraryPlaylist(let p), .catalogPlaylist(let p): return p.name
        }
    }

    var subtitle: String {
        switch self {
        case .librarySong(let s), .catalogSong(let s): return s.artistName
        case .libraryAlbum(let a), .catalogAlbum(let a): return a.artistName
        case .libraryArtist, .catalogArtist: return "Artist"
        case .libraryPlaylist(let p), .catalogPlaylist(let p): return p.curatorName ?? "Apple Music"
        }
    }

    var artwork: Artwork? {
        switch self {
        case .librarySong(let s), .catalogSong(let s): return s.artwork
        case .libraryAlbum(let a), .catalogAlbum(let a): return a.artwork
        case .libraryArtist(let a), .catalogArtist(let a): return a.artwork
        case .libraryPlaylist(let p), .catalogPlaylist(let p): return p.artwork
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
        }
    }

    var isLibrary: Bool {
        switch self {
        case .librarySong, .libraryAlbum, .libraryArtist, .libraryPlaylist: return true
        case .catalogSong, .catalogAlbum, .catalogArtist, .catalogPlaylist: return false
        }
    }

    static func == (lhs: SearchResultItem, rhs: SearchResultItem) -> Bool {
        lhs.id == rhs.id
    }
}
