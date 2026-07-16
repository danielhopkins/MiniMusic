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

    @Test("The named piece outranks its opus siblings, which outrank a miss")
    func tiers() {
        let ref = "Op. 28 No. 24"
        #expect(CatalogueReference.matchTier(
            title: "24 Préludes, Op. 28: No. 24 in D Minor", reference: ref) == 2)
        #expect(CatalogueReference.matchTier(
            title: "Preludes, Op. 28 & 24 Variations", reference: ref) == 1)
        #expect(CatalogueReference.matchTier(
            title: "Nocturne Op. 9, No. 2", reference: ref) == 0)
    }

    @Test("A set's size is not the movement number")
    func setSizeIsNotMovement() {
        // The "24" of "24 Préludes" counts the set. Reading it as the movement
        // ties every prelude in Op. 28 with the one actually asked for, which is
        // how a search for No. 24 came back led by No. 6 and No. 4.
        let ref = "Op. 28 No. 24"
        #expect(CatalogueReference.matchTier(
            title: "24 Préludes, Op. 28: No. 6 in B Minor", reference: ref) == 1)
        #expect(CatalogueReference.matchTier(
            title: "24 Preludes, Op. 28: No. 4 in E Minor", reference: ref) == 1)
        #expect(CatalogueReference.matchTier(
            title: "24 Préludes, Op. 28: No. 24 in D Minor", reference: ref) == 2)
    }

    @Test("A movement-first title still names the piece")
    func movementFirstOrdering() {
        // Apple Music mixes both orderings; only the pieces themselves are tier 2.
        #expect(CatalogueReference.matchTier(
            title: "Prélude No. 24 in D Minor, Op. 28", reference: "Op. 28 No. 24") == 2)
        #expect(CatalogueReference.matchTier(
            title: "Prélude No. 6 in B Minor, Op. 28", reference: "Op. 28 No. 24") == 1)
    }

    @Test("A key name is not read as a catalogue number")
    func keyNameIsNotACatalogue() {
        // "D" is Schubert's catalogue, but "in D Minor" is a key, not D. 24.
        #expect(CatalogueReference.matchTier(
            title: "Prelude in D Minor", reference: "D. 24") == 0)
        #expect(CatalogueReference.matchTier(
            title: "Impromptu in A-Flat Major, D. 899", reference: "D. 899") == 2)
    }

    @Test("A roman-numeral catalogue keeps its work number")
    func romanCatalogueWorkNumber() {
        #expect(CatalogueReference.matchTier(
            title: "Piano Sonata No. 62 in E-Flat Major, Hob. XVI:52",
            reference: "Hob. XVI 52") == 2)
        #expect(CatalogueReference.matchTier(
            title: "Piano Sonata No. 20 in C Minor, Hob. XVI:20",
            reference: "Hob. XVI 52") == 0)
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

    @Test("A bare ordinal names the movement on the work's own album")
    func bareOrdinalMovement() {
        // Real titles from "Chopin: Preludes, Op. 28" (Pogorelich): the album
        // carries the opus and each track numbers itself "24." with no "No.",
        // so matching the full reference finds nothing on the very album that
        // holds the piece.
        #expect(CatalogueReference.isMovement(
            title: "24 Préludes, Op. 28, 24. in D Minor", of: "op 28 no 24"))
        #expect(!CatalogueReference.isMovement(
            title: "24 Préludes, Op. 28, 6. in B Minor", of: "op 28 no 24"))
        #expect(!CatalogueReference.isMovement(
            title: "24 Préludes, Op. 28, 4. in E Minor", of: "op 28 no 24"))
    }

    @Test("Movement matching accepts the spelled-out and movement-first forms")
    func movementFormVariants() {
        #expect(CatalogueReference.isMovement(
            title: "24 Préludes, Op. 28: No. 24 in D Minor", of: "Op. 28 No. 24"))
        #expect(CatalogueReference.isMovement(
            title: "Prélude No. 24 in D Minor, Op. 28", of: "Op. 28 No. 24"))
        #expect(!CatalogueReference.isMovement(
            title: "24 Préludes, Op. 28: No. 15 in D-Flat Major", of: "Op. 28 No. 24"))
    }

    @Test("A work-only reference still needs a full match")
    func workOnlyReferenceMovement() {
        // "bwv 1041" names no movement, so every movement of the concerto is a
        // legitimate hit — but an unrelated work is not.
        #expect(CatalogueReference.movementNumber(of: "bwv 1041") == nil)
        #expect(CatalogueReference.isMovement(
            title: "Violin Concerto in A Minor, BWV 1041: I. Allegro", of: "bwv 1041"))
        #expect(!CatalogueReference.isMovement(
            title: "Violin Concerto in E Major, BWV 1042: I. Allegro", of: "bwv 1041"))
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
