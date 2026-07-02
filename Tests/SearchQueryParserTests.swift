import Testing
// `SearchQueryParser.swift` and `SearchCategory.swift` are compiled into this
// test target (see project.yml).

struct SearchQueryParserTests {

    @Test("Strips a trailing type keyword and scopes the search", arguments: [
        ("piano playlist", "piano", SearchCategory.playlist),
        ("swift artist", "swift", .artist),
        ("mozart album", "mozart", .album),
        ("jazz song", "jazz", .song),
        ("beethoven track", "beethoven", .song),
    ])
    func trailingKeyword(input: String, term: String, category: SearchCategory) {
        let result = SearchQueryParser.parse(input)
        #expect(result.term == term)
        #expect(result.categories == [category])
    }

    @Test("Strips a leading type keyword and scopes the search", arguments: [
        ("playlists piano", "piano", SearchCategory.playlist),
        ("songs beethoven", "beethoven", .song),
        ("artist swift", "swift", .artist),
    ])
    func leadingKeyword(input: String, term: String, category: SearchCategory) {
        let result = SearchQueryParser.parse(input)
        #expect(result.term == term)
        #expect(result.categories == [category])
    }

    @Test("Leaves a bare type word as a normal all-category search", arguments: [
        "playlist", "artist", "songs", "album",
    ])
    func bareKeyword(input: String) {
        let result = SearchQueryParser.parse(input)
        #expect(result.term == input)
        #expect(result.categories.isEmpty)
    }

    @Test("Treats queries with no type keyword as all-category", arguments: [
        "mozart", "the beatles", "relaxing music",
    ])
    func noKeyword(input: String) {
        let result = SearchQueryParser.parse(input)
        #expect(result.term == input)
        #expect(result.categories.isEmpty)
    }

    @Test("Matches keywords case-insensitively, preserving the term's case")
    func caseInsensitive() {
        let result = SearchQueryParser.parse("Piano PLAYLIST")
        #expect(result.term == "Piano")
        #expect(result.categories == [.playlist])
    }

    @Test("Trims surrounding whitespace")
    func whitespace() {
        let result = SearchQueryParser.parse("  swift artist  ")
        #expect(result.term == "swift")
        #expect(result.categories == [.artist])
    }
}
