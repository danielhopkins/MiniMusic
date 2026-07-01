import Testing
// `ComposerName.swift` is compiled into this test target (see project.yml).

struct ComposerNameTests {

    @Test("Abbreviates given names, keeps the surname", arguments: [
        ("Wolfgang Amadeus Mozart", "W. A. Mozart"),
        ("Frédéric Chopin", "F. Chopin"),
        ("Johann Sebastian Bach", "J. S. Bach"),
        ("Pyotr Ilyich Tchaikovsky", "P. I. Tchaikovsky"),
        ("Carl Philipp Emanuel Bach", "C. P. E. Bach"),
        ("Antonín Dvořák", "A. Dvořák"),
        ("Gustav Mahler", "G. Mahler"),
    ])
    func basics(input: String, expected: String) {
        #expect(ComposerName.abbreviated(input) == expected)
    }

    @Test("Keeps nobiliary particles with the surname", arguments: [
        ("Ludwig van Beethoven", "L. van Beethoven"),
        ("Manuel de Falla", "M. de Falla"),
    ])
    func particles(input: String, expected: String) {
        #expect(ComposerName.abbreviated(input) == expected)
    }

    @Test("Handles hyphenated given names")
    func hyphenated() {
        #expect(ComposerName.abbreviated("Jean-Philippe Rameau") == "J.-P. Rameau")
    }

    @Test("Keeps hyphenated surnames intact")
    func hyphenatedSurname() {
        #expect(ComposerName.abbreviated("Nikolai Rimsky-Korsakov") == "N. Rimsky-Korsakov")
        #expect(ComposerName.abbreviated("Camille Saint-Saëns") == "C. Saint-Saëns")
    }

    @Test("Keeps known two-word surnames intact")
    func compoundSurname() {
        #expect(ComposerName.abbreviated("Ralph Vaughan Williams") == "R. Vaughan Williams")
    }

    @Test("Leaves single-name composers unchanged", arguments: [
        "Vivaldi", "Pachelbel", "",
    ])
    func mononym(input: String) {
        #expect(ComposerName.abbreviated(input) == input)
    }

    @Test("Is idempotent on already-abbreviated names")
    func idempotent() {
        #expect(ComposerName.abbreviated("W. A. Mozart") == "W. A. Mozart")
        #expect(ComposerName.abbreviated("L. van Beethoven") == "L. van Beethoven")
    }
}
