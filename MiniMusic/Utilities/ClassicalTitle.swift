import Foundation

/// Formatting helpers for classical track titles.
enum ClassicalTitle {
    /// Common classical catalogue-number prefixes (Köchel, Opus, Bach-Werke,
    /// Hoboken, etc.). Matched case-sensitively since Apple Music capitalizes
    /// them, which avoids splitting on ordinary lowercase words.
    nonisolated private static let cataloguePrefixes = [
        "Opus", "Op", "KV", "K", "BWV", "BuxWV", "ZWV", "Hob", "HWV", "WAB",
        "RV", "WoO", "Anh", "TWV", "Wq", "Sz", "TrV", "JB", "BB", "FP", "VB",
        "Kk", "ZT", "BV", "D", "S", "B", "P", "T", "H", "G", "L", "M", "R", "Z",
    ]

    /// Splits a classical track title into a work name and an optional
    /// catalogue/section detail, breaking so the detail stays intact on its own
    /// line. Apple Music formats classical titles as `Work, Catalogue: Movement`
    /// (catalogue and/or movement may be absent). For example:
    ///
    ///   "Die Entführung aus dem Serail, K. 384: Overture"
    ///     → ("Die Entführung aus dem Serail", "K. 384: Overture")
    ///   "Liebesträume, S. 541: No. 3 in A-Flat Major"
    ///     → ("Liebesträume", "S. 541: No. 3 in A-Flat Major")
    ///   "Symphony No. 5 in C-Sharp Minor: IV. Adagietto"
    ///     → ("Symphony No. 5 in C-Sharp Minor", "IV. Adagietto")
    ///
    /// Breaks at the catalogue number when present, otherwise at the movement
    /// separator (": "). Returns `(title, nil)` when neither is found.
    nonisolated static func split(_ rawTitle: String) -> (work: String, detail: String?) {
        let title = formatAccidentals(rawTitle)
        if let split = splitAtCatalogue(title) {
            return split
        }
        if let split = splitAtMovement(title) {
            return split
        }
        return (title, nil)
    }

    /// Replaces spelled-out key accidentals with musical symbols, e.g.
    /// "A-Flat Major" → "A♭ Major", "C-Sharp Minor" → "C♯ Minor".
    nonisolated static func formatAccidentals(_ text: String) -> String {
        var result = text
        result = replacing(result, pattern: "(?<![A-Za-z])([A-G])[- ][Ff]lat", template: "$1\u{266D}")
        result = replacing(result, pattern: "(?<![A-Za-z])([A-G])[- ][Ss]harp", template: "$1\u{266F}")
        return result
    }

    private nonisolated static func replacing(_ text: String, pattern: String, template: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        return regex.stringByReplacingMatches(
            in: text, range: NSRange(text.startIndex..., in: text), withTemplate: template
        )
    }

    /// Breaks at a catalogue number, keeping the number and everything after it
    /// (including the movement) together as the detail. The catalogue is matched
    /// when preceded by a comma or a space, so both "Serail, K. 384: Overture"
    /// and "Valses nobles D. 969" split correctly. A note name followed by a key
    /// quality (e.g. "in D Major") can't match, since the prefix must be followed
    /// by a number or roman numeral.
    private nonisolated static func splitAtCatalogue(_ title: String) -> (work: String, detail: String?)? {
        let markers = cataloguePrefixes.joined(separator: "|")
        // A comma or space, the catalogue prefix, then a number or roman numeral.
        let pattern = "[,\\s]\\s*(?:\(markers))\\.?\\s*[0-9IVXLC]"

        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let matches = regex.matches(in: title, range: NSRange(title.startIndex..., in: title))

        for match in matches {
            guard let sepRange = Range(match.range, in: title) else { continue }
            let workPortion = title[..<sepRange.lowerBound]
            // Skip catalogue references inside parentheses (e.g. "(after RV 117)").
            if endsInsideParentheses(workPortion) { continue }

            let work = workPortion.trimmingCharacters(in: .whitespaces)
            var detail = String(title[sepRange.lowerBound...])
            if detail.hasPrefix(",") { detail.removeFirst() }
            detail = detail.trimmingCharacters(in: .whitespaces)

            if !work.isEmpty, !detail.isEmpty { return (work, detail) }
        }
        return nil
    }

    /// Breaks at the first movement separator (": ") for titles with no
    /// catalogue number, e.g. "Symphony No. 5 in C-Sharp Minor: IV. Adagietto".
    /// Skips separators inside parentheses (e.g. "(Live: 2020)").
    private nonisolated static func splitAtMovement(_ title: String) -> (work: String, detail: String?)? {
        var searchStart = title.startIndex
        while let range = title.range(of: ": ", range: searchStart..<title.endIndex) {
            let workPortion = title[..<range.lowerBound]
            if !endsInsideParentheses(workPortion) {
                let work = workPortion.trimmingCharacters(in: .whitespaces)
                let detail = title[range.upperBound...].trimmingCharacters(in: .whitespaces)
                if !work.isEmpty, !detail.isEmpty { return (work, detail) }
            }
            searchStart = range.upperBound
        }
        return nil
    }

    /// True when `text` ends with an unclosed "(" — i.e. a split here would land
    /// inside a parenthetical aside, breaking the parentheses across two lines.
    private nonisolated static func endsInsideParentheses(_ text: Substring) -> Bool {
        var depth = 0
        for character in text {
            if character == "(" { depth += 1 }
            else if character == ")" { depth = max(0, depth - 1) }
        }
        return depth > 0
    }
}
