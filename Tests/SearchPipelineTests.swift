import Testing
// End-to-end tests of the fallback (no-Apple-Intelligence) search pipeline:
// raw query → deterministic facets → strategy. `SearchPlanner.swift`,
// `SearchQueryParser.swift` and `SearchCategory.swift` are compiled into this
// test target (see project.yml).
//
// The model-driven path (artist/album/song facet extraction) requires a device
// with Apple Intelligence and can't run here; its routing is covered by
// SearchPlannerTests using representative facet inputs, and verified manually.

struct SearchPipelineTests {

    /// Mirrors what `MusicSearchViewModel` does when the model is unavailable.
    private func strategy(for query: String) -> SearchStrategy {
        SearchPlanner.plan(SearchFacets(deterministicallyParsing: query))
    }

    @Test("A type keyword scopes a text search", arguments: [
        ("piano playlist", "piano", SearchCategory.playlist),
        ("playlists piano", "piano", .playlist),
        ("swift artist", "swift", .artist),
        ("songs beethoven", "beethoven", .song),
    ])
    func keywordScopesText(query: String, term: String, category: SearchCategory) {
        #expect(strategy(for: query) == .text(term: term, categories: [category]))
    }

    @Test("A bare query is an all-category text search", arguments: [
        "mozart", "the beatles", "relaxing music",
    ])
    func bareQueryIsText(query: String) {
        #expect(strategy(for: query) == .text(term: query, categories: []))
    }

    @Test("The fallback parser misses a type word buried mid-sentence")
    func midSentenceKeywordMissed() {
        // "playlists" is neither the first nor last token, so without the model
        // this stays an all-category search — the case that motivates the model.
        let result = strategy(for: "classical playlists that are exciting")
        #expect(result == .text(term: "classical playlists that are exciting", categories: []))
    }

    @Test("Without the model, a natural-language query never resolves an album or artist")
    func fallbackNeverResolvesFacets() {
        // The deterministic parser has no artist/album facets, so even a rich
        // query like this stays a text search (here the trailing "album" keyword
        // scopes it to albums) rather than listing a resolved album's tracks.
        let result = strategy(for: "tailor swift songs from the red album")
        #expect(result == .text(term: "tailor swift songs from the red", categories: [.album]))

        // It is specifically NOT an album-track or artist-top-songs strategy.
        if case .text = result {} else {
            Issue.record("Fallback pipeline must only ever produce text strategies")
        }
    }
}
