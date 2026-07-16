import MusicKit
import SwiftUI
import Observation

@Observable final class MusicSearchViewModel {

    // MARK: - State

    var searchQuery = "" {
        didSet { debounceSearch() }
    }
    private(set) var songs: MusicItemCollection<Song> = []
    private(set) var albums: MusicItemCollection<Album> = []
    private(set) var artists: MusicItemCollection<Artist> = []
    private(set) var playlists: MusicItemCollection<Playlist> = []
    private(set) var librarySongs: MusicItemCollection<Song> = []
    private(set) var libraryAlbums: MusicItemCollection<Album> = []
    private(set) var libraryArtists: MusicItemCollection<Artist> = []
    private(set) var libraryPlaylists: MusicItemCollection<Playlist> = []
    private(set) var isLoading = false
    private(set) var errorMessage: String?

    /// Categories the current search is scoped to; empty means "everything",
    /// which triggers per-category result capping in `allResults`.
    private(set) var activeCategories: [SearchCategory] = []

    /// True when the on-device model shaped the current results, so the UI can
    /// show a subtle Apple Intelligence indicator.
    private(set) var usedIntelligence = false

    /// Mood/vibe the current search asked for; drives result over-fetching and
    /// the model re-rank pass. Empty for ordinary searches.
    private var activeDescriptor = ""

    /// Catalogue/opus reference parsed from the query ("Op. 28 No. 24"), used
    /// to float exact catalogue matches above Apple's fuzzy lexical ranking.
    /// Empty when the query names no catalogue reference.
    private var activeSongReference = ""

    /// Artist facet of the current search, kept for catalogue work resolution.
    private var activeArtist = ""

    /// Log of executed searches and what they returned. Owned here (and exposed
    /// so it can be injected into the environment) since every search flows
    /// through this view model.
    let history = SearchHistoryStore()

    var isEmpty: Bool {
        songs.isEmpty && albums.isEmpty && artists.isEmpty && playlists.isEmpty
            && librarySongs.isEmpty && libraryAlbums.isEmpty && libraryArtists.isEmpty
            && libraryPlaylists.isEmpty
    }

    var allResults: [SearchResultItem] {
        // A broad, unscoped search shows every category, so cap each one to keep
        // the list scannable. A scoped search ("piano playlist") shows all of the
        // one kind it fetched.
        let cap = activeCategories.isEmpty ? 3 : Int.max

        let libSongs = Array(librarySongs.prefix(cap))
        let libAlbums = Array(libraryAlbums.prefix(cap))
        let libArtists = Array(libraryArtists.prefix(cap))
        let libPlaylists = Array(libraryPlaylists.prefix(cap))

        let librarySongKeys = Set(libSongs.map { "\($0.title)\n\($0.artistName)" })
        let libraryAlbumKeys = Set(libAlbums.map { "\($0.title)\n\($0.artistName)" })
        let libraryArtistKeys = Set(libArtists.map { $0.name })
        let libraryPlaylistKeys = Set(libPlaylists.map { $0.name })

        let catSongs = songs.filter { !librarySongKeys.contains("\($0.title)\n\($0.artistName)") }
            .prefix(cap)
        let catAlbums = albums.filter { !libraryAlbumKeys.contains("\($0.title)\n\($0.artistName)") }
            .prefix(cap)
        let catArtists = artists.filter { !libraryArtistKeys.contains($0.name) }.prefix(cap)
        let catPlaylists = playlists.filter { !libraryPlaylistKeys.contains($0.name) }.prefix(cap)

        var items: [SearchResultItem] = []
        items += libSongs.map { .librarySong($0) }
        items += libAlbums.map { .libraryAlbum($0) }
        items += libArtists.map { .libraryArtist($0) }
        items += libPlaylists.map { .libraryPlaylist($0) }
        items += catSongs.map { .catalogSong($0) }
        items += catAlbums.map { .catalogAlbum($0) }
        items += catArtists.map { .catalogArtist($0) }
        items += catPlaylists.map { .catalogPlaylist($0) }
        return items
    }

    // MARK: - Private

    private var searchTask: Task<Void, Never>?
    private var debounceTask: Task<Void, Never>?
    private let intentParser = SearchIntentParser()

    // MARK: - Prewarm

    /// Warms the on-device intent model so the first smart search isn't cold.
    func prewarm() {
        intentParser.prewarm()
    }

    // MARK: - Debounce

    private func debounceSearch() {
        debounceTask?.cancel()
        searchTask?.cancel()
        let query = searchQuery
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.isEmpty {
            clearResults()
            return
        }

        debounceTask = Task {
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            performSearch(query: query)
        }
    }

    // MARK: - Search

    private func performSearch(query: String) {
        searchTask?.cancel()

        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            clearResults()
            return
        }

        searchTask = Task {
            isLoading = true
            errorMessage = nil

            // Resolve facets: an instant deterministic parse, refined into
            // structured facets by the on-device model when it's available.
            var facets = SearchFacets(deterministicallyParsing: trimmed)
            var refinedByModel = false
            if let intent = await intentParser.parse(trimmed),
               !intent.term.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                facets = intent.facets
                refinedByModel = true
            }

            guard !Task.isCancelled else { return }

            // Let the planner choose *how* to search from the facets.
            let strategy = SearchPlanner.plan(facets)
            usedIntelligence = refinedByModel
            activeDescriptor = facets.descriptor
            // A catalogue reference ("Op. 28 No. 24") can be ranked
            // deterministically once results arrive. Extract it from the song
            // facet, falling back to the raw query so ranking doesn't depend on
            // where the model chose to put (or drop) the reference.
            activeSongReference = CatalogueReference.extract(from: facets.song)
                ?? CatalogueReference.extract(from: trimmed) ?? ""
            activeArtist = facets.artist
            // Resolved-item strategies (album tracks, artist top songs) return a
            // single full list of songs, so disable the per-category cap.
            switch strategy {
            case .albumTracks, .artistTopSongs: activeCategories = [.song]
            case .artistAlbums: activeCategories = [.album]
            case .text(_, let categories): activeCategories = categories
            }

            await execute(strategy)

            if !Task.isCancelled {
                isLoading = false
                recordHistory(query: trimmed)
            }
        }
    }

    /// Logs the just-completed search and its result summary. Counts come from
    /// the raw collections (not the capped `allResults`) so history reflects
    /// everything the search actually returned.
    private func recordHistory(query: String) {
        let counts = SearchHistoryEntry.ResultCounts(
            librarySongs: librarySongs.count,
            libraryAlbums: libraryAlbums.count,
            libraryArtists: libraryArtists.count,
            libraryPlaylists: libraryPlaylists.count,
            songs: songs.count,
            albums: albums.count,
            artists: artists.count,
            playlists: playlists.count
        )
        let top = allResults.prefix(6).map { "\($0.title) — \($0.subtitle)" }
        history.record(
            query: query,
            usedIntelligence: usedIntelligence,
            counts: counts,
            topResults: top
        )
    }

    // MARK: - Strategy execution

    private func execute(_ strategy: SearchStrategy) async {
        switch strategy {
        case .albumTracks(let album, let artist):
            await performAlbumTrackSearch(album: album, artist: artist)
        case .artistTopSongs(let artist):
            await performArtistTopSongsSearch(artist: artist)
        case .artistAlbums(let artist):
            await performArtistAlbumsSearch(artist: artist)
        case .text(let term, let categories):
            await withTaskGroup(of: Void.self) { group in
                group.addTask { await self.performLibrarySearch(term: term, categories: categories) }
                group.addTask { await self.performCatalogSearch(term: term, categories: categories) }
            }
            // Apple's lexical search is fuzzy about catalogue numbers — a term
            // like "Chopin Op. 28 No. 24" often doesn't return the piece at
            // all. Resolve the work's album (titled at the work level, e.g.
            // "24 Préludes, Op. 28") to fetch the exact tracks, then float
            // titles containing the reference to the top.
            if !activeSongReference.isEmpty {
                await surfaceCatalogueWork(
                    activeSongReference, artist: activeArtist, term: term)
                boostCatalogueMatches(activeSongReference)
            }
            // The lexical search ignores mood words, so re-rank by the vibe.
            if !activeDescriptor.isEmpty {
                await rerankByVibe(activeDescriptor, query: term)
            }
        }
    }

    /// Fetches the exact tracks of a catalogue-referenced work by resolving its
    /// album — Apple catalogues works as albums titled with the work-level
    /// number — and prepends the tracks whose titles contain the full reference
    /// to the song results. Best-effort: any miss leaves the results untouched.
    private func surfaceCatalogueWork(_ reference: String, artist: String, term: String) async {
        let work = CatalogueReference.workLevel(reference)
        let searchTerm = artist.isEmpty ? term : "\(artist) \(work)"
        do {
            var request = MusicCatalogSearchRequest(term: searchTerm, types: [Album.self])
            request.limit = 10
            let response = try await request.response()
            guard !Task.isCancelled else { return }

            let candidates = CatalogueReference.ranked(
                Array(response.albums), reference: work, title: \.title)
            guard let album = candidates.first,
                  CatalogueReference.matchTier(title: album.title, reference: work) > 0
            else { return }

            let detailed = try await album.with([.tracks])
            guard !Task.isCancelled else { return }

            // The album is the work, so its tracks only have to supply the
            // movement — they routinely don't repeat the opus, and Apple writes
            // the number as a bare ordinal as often as "No. 24".
            let exact = (detailed.tracks ?? []).compactMap { track -> Song? in
                guard case .song(let song) = track,
                      CatalogueReference.isMovement(title: song.title, of: reference)
                else { return nil }
                return song
            }
            guard !exact.isEmpty else { return }

            let ids = Set(exact.map(\.id))
            songs = MusicItemCollection(exact + songs.filter { !ids.contains($0.id) })
        } catch {
            // Best-effort enrichment; the primary results stand on any failure.
        }
    }

    /// Reorders song and album results so titles containing the catalogue
    /// reference come first (library and catalog alike), keeping Apple's order
    /// within each match tier.
    private func boostCatalogueMatches(_ reference: String) {
        songs = MusicItemCollection(
            CatalogueReference.ranked(Array(songs), reference: reference, title: \.title))
        librarySongs = MusicItemCollection(
            CatalogueReference.ranked(Array(librarySongs), reference: reference, title: \.title))
        albums = MusicItemCollection(
            CatalogueReference.ranked(Array(albums), reference: reference, title: \.title))
        libraryAlbums = MusicItemCollection(
            CatalogueReference.ranked(Array(libraryAlbums), reference: reference, title: \.title))
    }

    /// Reorders catalog playlists and songs to match a requested vibe the text
    /// search couldn't honor, dropping clear mismatches. Leaves results untouched
    /// if the model declines or fails.
    private func rerankByVibe(_ vibe: String, query: String) async {
        let playlistArray = Array(playlists)
        if let kept = await intentParser.rerank(
            candidates: playlistArray.map { "\($0.name) — \($0.curatorName ?? "Apple Music")" },
            vibe: vibe, query: query
        ) {
            guard !Task.isCancelled else { return }
            playlists = MusicItemCollection(kept.map { playlistArray[$0] })
        }

        let songArray = Array(songs)
        if let kept = await intentParser.rerank(
            candidates: songArray.map { "\($0.title) — \($0.artistName)" },
            vibe: vibe, query: query
        ) {
            guard !Task.isCancelled else { return }
            songs = MusicItemCollection(kept.map { songArray[$0] })
        }
    }

    /// Resolves an album and lists its songs. Falls back to showing the matched
    /// albums themselves if tracks can't be loaded.
    private func performAlbumTrackSearch(album: String, artist: String) async {
        resetCollections()
        do {
            let term = artist.isEmpty ? album : "\(album) \(artist)"
            var request = MusicCatalogSearchRequest(term: term, types: [Album.self])
            request.limit = 10
            let response = try await request.response()
            guard !Task.isCancelled else { return }

            guard let matched = bestAlbum(in: response.albums, artist: artist) else {
                albums = response.albums
                return
            }

            let detailed = try await matched.with([.tracks])
            guard !Task.isCancelled else { return }

            let albumSongs = (detailed.tracks ?? []).compactMap { track -> Song? in
                if case .song(let song) = track { return song }
                return nil
            }
            songs = MusicItemCollection(albumSongs)
        } catch is CancellationError {
            // Ignored — superseded by a newer query.
        } catch {
            guard !Task.isCancelled else { return }
            errorMessage = error.localizedDescription
        }
    }

    /// Resolves an artist and lists their top songs. Falls back to showing the
    /// matched artists themselves if top songs can't be loaded.
    private func performArtistTopSongsSearch(artist: String) async {
        resetCollections()
        do {
            var request = MusicCatalogSearchRequest(term: artist, types: [Artist.self])
            request.limit = 5
            let response = try await request.response()
            guard !Task.isCancelled else { return }

            guard let matched = response.artists.first else {
                artists = response.artists
                return
            }

            let detailed = try await matched.with([.topSongs])
            guard !Task.isCancelled else { return }
            songs = detailed.topSongs ?? []
        } catch is CancellationError {
            // Ignored — superseded by a newer query.
        } catch {
            guard !Task.isCancelled else { return }
            errorMessage = error.localizedDescription
        }
    }

    /// Resolves an artist and lists their albums (discography). Falls back to
    /// showing the matched artists themselves if albums can't be loaded.
    private func performArtistAlbumsSearch(artist: String) async {
        resetCollections()
        do {
            var request = MusicCatalogSearchRequest(term: artist, types: [Artist.self])
            request.limit = 5
            let response = try await request.response()
            guard !Task.isCancelled else { return }

            guard let matched = response.artists.first else {
                artists = response.artists
                return
            }

            let detailed = try await matched.with([.albums])
            guard !Task.isCancelled else { return }
            albums = detailed.albums ?? []
        } catch is CancellationError {
            // Ignored — superseded by a newer query.
        } catch {
            guard !Task.isCancelled else { return }
            errorMessage = error.localizedDescription
        }
    }

    /// Picks the album best matching the requested artist, falling back to the
    /// first result when no artist was named or none matches.
    private func bestAlbum(in albums: MusicItemCollection<Album>, artist: String) -> Album? {
        guard !artist.isEmpty else { return albums.first }
        let match = albums.first { $0.artistName.localizedCaseInsensitiveContains(artist) }
        return match ?? albums.first
    }

    private func performLibrarySearch(term: String, categories: [SearchCategory]) async {
        let wanted = categories.isEmpty ? Set(SearchCategory.allCases) : Set(categories)
        // A scoped search shows only one kind, so it can afford a deeper list.
        let limit = categories.isEmpty ? 5 : 15
        do {
            if wanted.contains(.song) {
                var request = MusicLibrarySearchRequest(term: term, types: [Song.self])
                request.limit = limit
                let response = try await request.response()
                guard !Task.isCancelled else { return }
                librarySongs = response.songs
            } else {
                librarySongs = []
            }

            if wanted.contains(.album) {
                var request = MusicLibrarySearchRequest(term: term, types: [Album.self])
                request.limit = limit
                let response = try await request.response()
                guard !Task.isCancelled else { return }
                libraryAlbums = response.albums
            } else {
                libraryAlbums = []
            }

            if wanted.contains(.artist) {
                var request = MusicLibrarySearchRequest(term: term, types: [Artist.self])
                request.limit = limit
                let response = try await request.response()
                guard !Task.isCancelled else { return }
                libraryArtists = response.artists
            } else {
                libraryArtists = []
            }

            if wanted.contains(.playlist) {
                var request = MusicLibrarySearchRequest(term: term, types: [Playlist.self])
                request.limit = limit
                let response = try await request.response()
                guard !Task.isCancelled else { return }
                libraryPlaylists = response.playlists
            } else {
                libraryPlaylists = []
            }
        } catch is CancellationError {
            // Ignored
        } catch {
            guard !Task.isCancelled else { return }
            // Library search errors are non-fatal; catalog results still show
        }
    }

    private func performCatalogSearch(term: String, categories: [SearchCategory]) async {
        let wanted = categories.isEmpty ? Set(SearchCategory.allCases) : Set(categories)
        // Over-fetch when re-ranking by a vibe, so the model has candidates to
        // pick the best matches from even on a broad search.
        let limit = categories.isEmpty ? (activeDescriptor.isEmpty ? 6 : 25) : 25

        var types: [any MusicCatalogSearchable.Type] = []
        if wanted.contains(.song) { types.append(Song.self) }
        if wanted.contains(.album) { types.append(Album.self) }
        if wanted.contains(.artist) { types.append(Artist.self) }
        if wanted.contains(.playlist) { types.append(Playlist.self) }

        do {
            var request = MusicCatalogSearchRequest(term: term, types: types)
            request.limit = limit

            let response = try await request.response()

            guard !Task.isCancelled else { return }

            // Types not requested simply come back empty in the response.
            songs = response.songs
            albums = response.albums
            artists = response.artists
            playlists = response.playlists
        } catch is CancellationError {
            // Ignored — search was superseded by a newer query.
        } catch {
            guard !Task.isCancelled else { return }
            errorMessage = error.localizedDescription
        }
    }

    /// Zeroes every result collection without touching loading/error/intent
    /// state — used between strategies within a single search.
    private func resetCollections() {
        songs = []
        albums = []
        artists = []
        playlists = []
        librarySongs = []
        libraryAlbums = []
        libraryArtists = []
        libraryPlaylists = []
    }

    func clearResults() {
        resetCollections()
        activeCategories = []
        activeDescriptor = ""
        usedIntelligence = false
        isLoading = false
        errorMessage = nil
    }
}
