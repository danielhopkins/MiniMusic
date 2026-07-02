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

    /// Abbreviates a composer credit's given names to initials while keeping the
    /// surname (and any nobiliary particle) intact, to save horizontal space:
    ///
    ///   "Wolfgang Amadeus Mozart" → "W. A. Mozart"
    ///   "Ludwig van Beethoven"    → "L. van Beethoven"
    ///   "Jean-Philippe Rameau"    → "J.-P. Rameau"
    ///   "Ralph Vaughan Williams"  → "R. Vaughan Williams"
    ///
    /// When the credit lists several composers joined by "&", "/" or ";", each
    /// is abbreviated independently ("Percy Grainger & Edvard Grieg" →
    /// "P. Grainger & E. Grieg"). Single-name composers ("Vivaldi") are
    /// returned unchanged.
    nonisolated static func abbreviated(_ name: String) -> String {
        // Split on multi-composer separators, abbreviating each name in place
        // and leaving the separators (and surrounding spacing) untouched.
        guard let regex = try? NSRegularExpression(pattern: "[^&/;]+") else {
            return abbreviateOne(name)
        }
        let ns = name as NSString
        let matches = regex.matches(in: name, range: NSRange(location: 0, length: ns.length))
        guard matches.count > 1 else { return abbreviateOne(name) }

        let result = NSMutableString(string: name)
        for match in matches.reversed() {
            let segment = ns.substring(with: match.range)
            let lead = String(segment.prefix(while: { $0 == " " }))
            let trail = String(segment.reversed().prefix(while: { $0 == " " }))
            let core = segment.trimmingCharacters(in: .whitespaces)
            guard !core.isEmpty else { continue }
            result.replaceCharacters(in: match.range, with: lead + abbreviateOne(core) + trail)
        }
        return result as String
    }

    /// Abbreviates a single composer name (no multi-composer separators).
    nonisolated private static func abbreviateOne(_ name: String) -> String {
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
