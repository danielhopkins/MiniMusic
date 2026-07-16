import Testing
// `SearchPlanner.swift` and `SearchCategory.swift` are compiled into this test
// target (see project.yml).

struct SearchPlannerTests {

    @Test("A named album with no specific song lists the album's tracks")
    func albumTracks() {
        let facets = SearchFacets(term: "Taylor Swift Red", artist: "Taylor Swift",
                                  album: "Red", categories: [.song])
        #expect(SearchPlanner.plan(facets) == .albumTracks(album: "Red", artist: "Taylor Swift"))
    }

    @Test("An album wins even when the artist is unknown")
    func albumWithoutArtist() {
        let facets = SearchFacets(term: "Rumours", album: "Rumours")
        #expect(SearchPlanner.plan(facets) == .albumTracks(album: "Rumours", artist: ""))
    }

    @Test("A soundtrack/musical resolves to its album's tracks")
    func soundtrackAlbumTracks() {
        // "songs from the matilda netflix musical": the model routes the
        // production's soundtrack into the album facet, so we list its tracks.
        let facets = SearchFacets(term: "Matilda the Musical",
                                  album: "Matilda the Musical Netflix Soundtrack",
                                  categories: [.song])
        #expect(SearchPlanner.plan(facets)
            == .albumTracks(album: "Matilda the Musical Netflix Soundtrack", artist: ""))
    }

    @Test("A named artist wanting songs lists their top songs")
    func artistTopSongs() {
        let facets = SearchFacets(term: "Taylor Swift", artist: "Taylor Swift",
                                  categories: [.song])
        #expect(SearchPlanner.plan(facets) == .artistTopSongs(artist: "Taylor Swift"))
    }

    @Test("An album wins over an artist when both are named")
    func albumBeatsArtist() {
        let facets = SearchFacets(term: "Taylor Swift Red", artist: "Taylor Swift",
                                  album: "Red", categories: [.song])
        #expect(SearchPlanner.plan(facets) == .albumTracks(album: "Red", artist: "Taylor Swift"))
    }

    @Test("A named artist wanting albums lists their discography")
    func artistAlbums() {
        let facets = SearchFacets(term: "Taylor Swift", artist: "Taylor Swift",
                                  categories: [.album])
        #expect(SearchPlanner.plan(facets) == .artistAlbums(artist: "Taylor Swift"))
    }

    @Test("A specific song falls through to a text search, not top songs")
    func specificSongIsText() {
        let facets = SearchFacets(term: "Anti-Hero Taylor Swift", artist: "Taylor Swift",
                                  song: "Anti-Hero", categories: [.song])
        #expect(SearchPlanner.plan(facets) == .text(term: "Anti-Hero Taylor Swift", categories: [.song]))
    }

    @Test("A specific song beats a named album (no album-track listing)")
    func specificSongBeatsAlbum() {
        let facets = SearchFacets(term: "All Too Well Red", artist: "Taylor Swift",
                                  album: "Red", song: "All Too Well", categories: [.song])
        #expect(SearchPlanner.plan(facets) == .text(term: "All Too Well Red", categories: [.song]))
    }

    @Test("An artist wanting songs beyond just songs stays a text search")
    func artistWithMixedCategories() {
        // Categories other than exactly [.song] shouldn't trigger top-songs.
        let facets = SearchFacets(term: "Taylor Swift", artist: "Taylor Swift",
                                  categories: [.song, .album])
        #expect(SearchPlanner.plan(facets) == .text(term: "Taylor Swift", categories: [.song, .album]))
    }

    @Test("An artist with no explicit song scope stays a text search")
    func artistWithoutSongScope() {
        let facets = SearchFacets(term: "Taylor Swift", artist: "Taylor Swift")
        #expect(SearchPlanner.plan(facets) == .text(term: "Taylor Swift", categories: []))
    }

    @Test("A catalogue reference in the term routes to text even if the song facet is dropped")
    func catalogueReferenceInTermIsText() {
        // The model intermittently returns "bach bwv 1041" with an empty `song`
        // facet while keeping the reference in `term`. Without reading `term`,
        // this routes to the artist's top songs and BWV 1041 never surfaces.
        let facets = SearchFacets(term: "Bach BWV 1041", artist: "Bach", categories: [.song])
        #expect(SearchPlanner.plan(facets) == .text(term: "Bach BWV 1041", categories: [.song]))
    }

    @Test("A catalogue reference beats an artist's discography scope")
    func catalogueReferenceBeatsArtistAlbums() {
        let facets = SearchFacets(term: "Chopin Op. 28", artist: "Chopin", categories: [.album])
        #expect(SearchPlanner.plan(facets) == .text(term: "Chopin Op. 28", categories: [.album]))
    }

    @Test("A named work number keeps an artist query out of top songs")
    func workNumberIsText() {
        let facets = SearchFacets(term: "Beethoven Symphony No. 5", artist: "Beethoven",
                                  categories: [.song])
        #expect(SearchPlanner.plan(facets)
            == .text(term: "Beethoven Symphony No. 5", categories: [.song]))
    }

    @Test("A year or number in the term doesn't fake a catalogue reference")
    func plainNumberIsNotAReference() {
        // "1989" is an album, not an opus number — the album route must survive.
        let facets = SearchFacets(term: "Taylor Swift 1989", artist: "Taylor Swift",
                                  album: "1989", categories: [.song])
        #expect(SearchPlanner.plan(facets) == .albumTracks(album: "1989", artist: "Taylor Swift"))
    }

    @Test("A plain query with a category filter is a text search")
    func plainCategoryFilter() {
        let facets = SearchFacets(term: "piano", categories: [.playlist])
        #expect(SearchPlanner.plan(facets) == .text(term: "piano", categories: [.playlist]))
    }

    @Test("A descriptor (mood) doesn't change routing — still a scoped text search")
    func descriptivePlaylistRequest() {
        // Represents the model's output for "classical playlists that are
        // exciting": subject in `term`, mood in `descriptor`. The descriptor
        // drives a post-fetch re-rank, not routing, so this stays a text search.
        let facets = SearchFacets(term: "classical", descriptor: "exciting", categories: [.playlist])
        #expect(SearchPlanner.plan(facets) == .text(term: "classical", categories: [.playlist]))
    }

    @Test("A bare term is a text search across all categories")
    func bareTerm() {
        let facets = SearchFacets(term: "mozart")
        #expect(SearchPlanner.plan(facets) == .text(term: "mozart", categories: []))
    }
}
