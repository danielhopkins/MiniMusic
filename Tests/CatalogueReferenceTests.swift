import Testing
// `CatalogueReference.swift` is compiled into this test target (see project.yml).

struct CatalogueReferenceTests {

    @Test("Recognizes catalogue references", arguments: [
        "Op. 28 No. 24", "op 28 no 24", "BWV 1041", "K. 466", "k 466",
        "Op. 111", "Hob. XVI 52", "Opus 28 Nr 4", "D. 969", "S. 541",
    ])
    func references(text: String) {
        #expect(CatalogueReference.isReference(text))
    }

    @Test("Rejects titles and non-references", arguments: [
        "", "Bohemian Rhapsody", "Prelude No. 24", "99 Luftballons",
        "Nocturne", "Op cit", "greatest hits",
    ])
    func nonReferences(text: String) {
        #expect(!CatalogueReference.isReference(text))
    }

    @Test("Extracts an embedded reference", arguments: [
        ("chopin op 28 no 24", "op 28 no 24"),
        ("Prelude Op. 28 No. 24", "op 28 no 24"),
        ("bach bwv 1041", "bwv 1041"),
        ("schubert d 969", "d 969"),
        ("mozart k 466 piano concerto", "k 466"),
        ("haydn hob xvi 52", "hob xvi 52"),
    ])
    func extraction(text: String, expected: String) {
        #expect(CatalogueReference.extract(from: text) == expected)
    }

    @Test("Extracts nothing from titles, keys, and counts", arguments: [
        "", "Bohemian Rhapsody", "prelude in d minor", "symphony 9 d minor",
        "99 luftballons", "top 10 chopin", "chopin nocturne",
    ])
    func noExtraction(text: String) {
        #expect(CatalogueReference.extract(from: text) == nil)
    }

    @Test("Work-level reference strips a trailing movement clause", arguments: [
        ("op 28 no 24", "op 28"),
        ("Op. 27 No. 2", "op 27"),
        ("bwv 1041", "bwv 1041"),
        ("op 111", "op 111"),
        ("hob xvi 52", "hob xvi 52"),
    ])
    func workLevel(reference: String, expected: String) {
        #expect(CatalogueReference.workLevel(reference) == expected)
    }

    @Test("Exact contiguous match outranks number-only match outranks miss")
    func tiers() {
        let ref = "Op. 28 No. 24"
        #expect(CatalogueReference.matchTier(
            title: "24 Préludes, Op. 28: No. 24 in D Minor", reference: ref) == 2)
        #expect(CatalogueReference.matchTier(
            title: "Preludes, Op. 28 & 24 Variations", reference: ref) == 1)
        #expect(CatalogueReference.matchTier(
            title: "Nocturne Op. 9, No. 2", reference: ref) == 0)
    }

    @Test("Matches across alias spellings and punctuation")
    func aliases() {
        #expect(CatalogueReference.matchTier(
            title: "Violin Concerto in A Minor, BWV 1041: I. Allegro",
            reference: "bwv 1041") == 2)
        #expect(CatalogueReference.matchTier(
            title: "Piano Concerto No. 20 in D Minor, KV 466",
            reference: "K. 466") == 2)
        #expect(CatalogueReference.matchTier(
            title: "Preludes, Opus 28: No. 4 in E Minor",
            reference: "Op. 28 No. 4") == 2)
    }

    @Test("Ranks matches first, keeps original order within tiers")
    func ranking() {
        let titles = [
            "Nocturne in E-Flat Major, Op. 9 No. 2",
            "24 Préludes, Op. 28: No. 24 in D Minor",
            "Minute Waltz",
            "Préludes, Op. 28: No. 24",
            "Fantaisie-Impromptu",
        ]
        let ranked = CatalogueReference.ranked(
            titles, reference: "Op. 28 No. 24", title: { $0 })
        #expect(ranked == [
            "24 Préludes, Op. 28: No. 24 in D Minor",
            "Préludes, Op. 28: No. 24",
            "Nocturne in E-Flat Major, Op. 9 No. 2",
            "Minute Waltz",
            "Fantaisie-Impromptu",
        ])
    }
}
