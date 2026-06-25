import Testing
// `ClassicalTitle.swift` is compiled directly into this test target (see
// project.yml), so it's available without importing the app module — which
// keeps these as fast, hostless logic tests.

/// Cases derived from auditing ~6,000 real Apple Music classical titles.
struct ClassicalTitleTests {

    // MARK: - Catalogue split (comma-separated)

    @Test("Splits at a comma before the catalogue number")
    func commaCatalogue() {
        let r = ClassicalTitle.split("Die Entführung aus dem Serail, K. 384: Overture")
        #expect(r.work == "Die Entführung aus dem Serail")
        #expect(r.detail == "K. 384: Overture")
    }

    @Test("Keeps catalogue and movement together on the detail line")
    func catalogueWithMovement() {
        let r = ClassicalTitle.split("Symphony No. 9 in D Minor, Op. 125: IV. Presto")
        #expect(r.work == "Symphony No. 9 in D Minor")
        #expect(r.detail == "Op. 125: IV. Presto")
    }

    @Test("Liszt Searle (S.) catalogue splits")
    func searleCatalogue() {
        let r = ClassicalTitle.split("Liebesträume, S. 541: No. 3 in A-Flat Major")
        #expect(r.work == "Liebesträume")
        #expect(r.detail == "S. 541: No. 3 in A♭ Major")
    }

    @Test("First catalogue wins when several are present")
    func firstCatalogueWins() {
        let r = ClassicalTitle.split("12 Concerti Grossi, Op. 6: No. 3 in E Minor, HWV 321: II. Andante")
        #expect(r.work == "12 Concerti Grossi")
        #expect(r.detail == "Op. 6: No. 3 in E Minor, HWV 321: II. Andante")
    }

    // MARK: - Catalogue split (space-separated)

    @Test("Splits at a space before the catalogue number")
    func spaceCatalogue() {
        let r = ClassicalTitle.split("12 Valses nobles D. 969")
        #expect(r.work == "12 Valses nobles")
        #expect(r.detail == "D. 969")
    }

    @Test("Splits when only a space precedes the catalogue (no comma)")
    func exsultate() {
        let r = ClassicalTitle.split("Exsultate, Jubilate! K. 165")
        #expect(r.work == "Exsultate, Jubilate!")
        #expect(r.detail == "K. 165")
    }

    // MARK: - Movement (colon) fallback

    @Test("Falls back to splitting at the movement separator")
    func movementColon() {
        let r = ClassicalTitle.split("Symphony No. 5 in C-Sharp Minor: IV. Adagietto")
        #expect(r.work == "Symphony No. 5 in C♯ Minor")
        #expect(r.detail == "IV. Adagietto")
    }

    // MARK: - No split

    @Test("Leaves a plain title untouched")
    func noSplit() {
        let r = ClassicalTitle.split("Clair de lune")
        #expect(r.work == "Clair de lune")
        #expect(r.detail == nil)
    }

    @Test("A key name alone is not mistaken for a catalogue")
    func keyIsNotCatalogue() {
        let r = ClassicalTitle.split("Hungarian Dance No. 5 in G Minor")
        #expect(r.work == "Hungarian Dance No. 5 in G Minor")
        #expect(r.detail == nil)
    }

    // MARK: - Parenthesis guard

    @Test("Does not split on a catalogue reference inside parentheses")
    func catalogueInParentheses() {
        let title = "Aria (After Serenata Veneziana from Andromeda liberata, RV Anh. 117 by Vivaldi)"
        let r = ClassicalTitle.split(title)
        #expect(r.work == title)
        #expect(r.detail == nil)
    }

    @Test("Derivative track keeps the referenced work's catalogue inline")
    func derivativeReference() {
        let title = "Vivaldi - Spring (After The Four Seasons, RV 269)"
        let r = ClassicalTitle.split(title)
        #expect(r.detail == nil)
    }

    // MARK: - Accidentals

    @Test("Converts spelled-out accidentals to musical symbols", arguments: [
        ("No. 3 in A-Flat Major", "No. 3 in A♭ Major"),
        ("Étude in C-Sharp Minor", "Étude in C♯ Minor"),
        ("Prelude in D-Flat Major", "Prelude in D♭ Major"),
        ("Sonata in F-Sharp Minor", "Sonata in F♯ Minor"),
    ])
    func accidentals(input: String, expected: String) {
        #expect(ClassicalTitle.formatAccidentals(input) == expected)
    }

    @Test("Leaves ordinary hyphenated words alone")
    func hyphenNotAccidental() {
        // "Self-Flatter" must not become "Self♭ter".
        #expect(ClassicalTitle.formatAccidentals("Theme and Variations") == "Theme and Variations")
    }
}
