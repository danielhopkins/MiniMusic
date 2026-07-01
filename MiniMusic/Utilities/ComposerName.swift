import Foundation

/// Formatting helpers for composer names.
enum ComposerName {
    /// Lowercase nobiliary particles that belong with the surname rather than
    /// being abbreviated (e.g. the "van" in "Ludwig van Beethoven").
    nonisolated private static let particles: Set<String> = [
        "van", "von", "der", "den", "de", "del", "della", "di", "da", "dal",
        "du", "des", "le", "la", "ten", "ter", "y", "e",
    ]

    /// Surnames written as two words that must be kept intact (otherwise the
    /// first word would be wrongly abbreviated to an initial).
    nonisolated private static let compoundSurnames: Set<String> = [
        "vaughan williams", "mendelssohn bartholdy",
    ]

    /// Abbreviates a composer's given names to initials while keeping the
    /// surname (and any nobiliary particle) intact, to save horizontal space:
    ///
    ///   "Wolfgang Amadeus Mozart" → "W. A. Mozart"
    ///   "Ludwig van Beethoven"    → "L. van Beethoven"
    ///   "Jean-Philippe Rameau"    → "J.-P. Rameau"
    ///   "Ralph Vaughan Williams"  → "R. Vaughan Williams"
    ///
    /// Single-name composers ("Vivaldi") are returned unchanged.
    nonisolated static func abbreviated(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        let parts = trimmed.split(separator: " ").map(String.init)
        guard parts.count > 1 else { return trimmed }

        var surnameStart = parts.count - 1

        // Keep a known two-word surname together.
        if surnameStart >= 1 {
            let lastTwo = "\(parts[surnameStart - 1]) \(parts[surnameStart])".lowercased()
            if compoundSurnames.contains(lastTwo) { surnameStart -= 1 }
        }
        // Absorb preceding nobiliary particles ("van", "von der", …).
        while surnameStart - 1 >= 1, particles.contains(parts[surnameStart - 1].lowercased()) {
            surnameStart -= 1
        }
        // Need at least one leading given name to abbreviate.
        guard surnameStart >= 1 else { return trimmed }

        let given = parts[0..<surnameStart].map(initial(for:))
        let surname = parts[surnameStart...]
        return (given + surname).joined(separator: " ")
    }

    /// Turns a given name into an initial, preserving hyphenation
    /// ("Jean-Philippe" → "J.-P.") and leaving existing initials alone ("C." → "C.").
    nonisolated private static func initial(for token: String) -> String {
        if token.hasSuffix(".") { return token }
        let initials = token.split(separator: "-").compactMap { segment -> String? in
            guard let first = segment.first else { return nil }
            return "\(first)."
        }
        return initials.isEmpty ? token : initials.joined(separator: "-")
    }
}
