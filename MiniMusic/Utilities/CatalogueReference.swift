import Foundation

/// Matching helpers for classical catalogue references ("Op. 28 No. 24",
/// "BWV 1041") that the intent parser places in the `song` facet. Apple Music's
/// lexical search is fuzzy about numbers — searching "Chopin Op. 28 No. 24"
/// returns nocturnes before the prelude actually numbered 24 — so results are
/// re-ranked locally: titles that contain the reference float to the top.
enum CatalogueReference {
    /// Alternate spellings folded onto one canonical token before comparison.
    nonisolated private static let aliases: [String: String] = [
        "opus": "op", "nr": "no", "kv": "k",
    ]

    /// Lowercased catalogue words, from the same prefix list `ClassicalTitle`
    /// splits titles with (plus number words like "no").
    nonisolated private static let catalogueWords: Set<String> = {
        var words = Set(ClassicalTitle.cataloguePrefixes.map { $0.lowercased() })
        words.formUnion(["no", "nr", "opus"])
        return words
    }()

    /// True when `text` reads as a catalogue/opus reference rather than a song
    /// title: it contains at least one number, and every other token is a known
    /// catalogue word (or a roman numeral, for forms like "Hob. XVI 52").
    /// "Op. 28 No. 24" and "BWV 1041" qualify; "Prelude No. 24" and
    /// "99 Luftballons" don't, so real titles are never mistaken for references.
    nonisolated static func isReference(_ text: String) -> Bool {
        let tokens = normalize(text)
        guard tokens.contains(where: isNumber) else { return false }
        return tokens.allSatisfy { token in
            isNumber(token) || catalogueWords.contains(token) || isRoman(token)
        }
    }

    /// Extracts the catalogue reference embedded in `text`, if any: the longest
    /// run of catalogue words and numbers in which some catalogue word is
    /// immediately followed by a number (the "Op. 28" / "BWV 1041" shape, which
    /// also keeps key names like "d minor" or counts like "9 symphonies" from
    /// matching). Works on raw queries ("chopin op 28 no 24" → "op 28 no 24")
    /// and on song facets that mix a title with a reference
    /// ("Prelude Op. 28 No. 24" → "op 28 no 24"). Returns nil when `text`
    /// carries no reference.
    nonisolated static func extract(from text: String) -> String? {
        let tokens = normalize(text)
        var best: [String] = []
        var run: [String] = []
        func flush() {
            if qualifies(run), run.count > best.count { best = run }
            run = []
        }
        for token in tokens {
            if isNumber(token) || isRoman(token) || catalogueWords.contains(token) {
                run.append(token)
            } else {
                flush()
            }
        }
        flush()
        return best.isEmpty ? nil : best.joined(separator: " ")
    }

    /// The work-level portion of a reference: strips a trailing movement/number
    /// clause ("op 28 no 24" → "op 28") so album titles — which Apple Music
    /// catalogues at the work level ("24 Préludes, Op. 28") — can be matched.
    /// References without a trailing "no" clause are returned unchanged.
    nonisolated static func workLevel(_ reference: String) -> String {
        var tokens = normalize(reference)
        if tokens.count >= 4, tokens[tokens.count - 2] == "no", isNumber(tokens[tokens.count - 1]) {
            tokens.removeLast(2)
        }
        return tokens.joined(separator: " ")
    }

    /// True when some catalogue word in the run is immediately followed by a
    /// number or roman numeral — the syntactic core of a catalogue reference.
    nonisolated private static func qualifies(_ run: [String]) -> Bool {
        zip(run, run.dropFirst()).contains { word, next in
            catalogueWords.contains(word) && (isNumber(next) || isRoman(next))
        }
    }

    /// How well `title` matches `reference`: 2 when the reference's tokens
    /// appear contiguously in the title ("…, Op. 28: No. 24 in D Minor"),
    /// 1 when all of the reference's numbers appear somewhere in the title
    /// (the "24 Préludes, Op. 28" album), 0 otherwise.
    nonisolated static func matchTier(title: String, reference: String) -> Int {
        let ref = normalize(reference)
        guard !ref.isEmpty else { return 0 }
        let hay = normalize(title)
        if containsContiguous(hay, ref) { return 2 }
        let numbers = ref.filter(isNumber)
        if !numbers.isEmpty, numbers.allSatisfy(hay.contains) { return 1 }
        return 0
    }

    /// Reorders `items` so stronger matches for `reference` come first, keeping
    /// the original order within each tier.
    nonisolated static func ranked<T>(
        _ items: [T], reference: String, title: (T) -> String
    ) -> [T] {
        items.enumerated()
            .map { (item: $0.element, tier: matchTier(title: title($0.element), reference: reference), index: $0.offset) }
            .sorted { $0.tier != $1.tier ? $0.tier > $1.tier : $0.index < $1.index }
            .map(\.item)
    }

    /// Lowercased, diacritic-folded, alias-canonicalized tokens split on
    /// anything non-alphanumeric ("Op. 28: No. 24" → ["op","28","no","24"]).
    nonisolated private static func normalize(_ text: String) -> [String] {
        text.folding(options: .diacriticInsensitive, locale: nil)
            .lowercased()
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map { aliases[String($0)] ?? String($0) }
    }

    nonisolated private static func isNumber(_ token: String) -> Bool {
        token.allSatisfy(\.isNumber)
    }

    nonisolated private static func isRoman(_ token: String) -> Bool {
        !token.isEmpty && token.allSatisfy { "ivxlc".contains($0) }
    }

    nonisolated private static func containsContiguous(_ haystack: [String], _ needle: [String]) -> Bool {
        guard needle.count <= haystack.count else { return false }
        for start in 0...(haystack.count - needle.count)
        where Array(haystack[start..<(start + needle.count)]) == needle {
            return true
        }
        return false
    }
}
