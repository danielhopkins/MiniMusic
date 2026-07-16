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

    /// True when `title` — a track from the album of `reference`'s work — is the
    /// movement `reference` names.
    ///
    /// Tracks can't be matched on the whole reference, because the album carries
    /// the opus and the track often doesn't repeat it. Apple also writes the
    /// movement two ways: "Op. 28: No. 24 in D Minor", and, on the recording that
    /// actually holds the Op. 28 set, a bare ordinal — "24 Préludes, Op. 28, 24.
    /// in D Minor". Only the movement number is reliably present, so that's what
    /// this compares. A reference that names no movement ("BWV 1041") falls back
    /// to a full match.
    nonisolated static func isMovement(title: String, of reference: String) -> Bool {
        guard let wanted = movementNumber(of: reference) else {
            return matchTier(title: title, reference: reference) == 2
        }
        return movementNumber(inTitle: title, work: workLevel(reference)) == wanted
    }

    /// The movement number a reference names ("op 28 no 24" → "24"), or nil when
    /// it names only a work ("bwv 1041"). The mirror of `workLevel`.
    nonisolated static func movementNumber(of reference: String) -> String? {
        let tokens = normalize(reference)
        guard tokens.count >= 4, tokens[tokens.count - 2] == "no",
              isNumber(tokens[tokens.count - 1])
        else { return nil }
        return tokens[tokens.count - 1]
    }

    /// The movement `title` names within `work`: the number right after the work's
    /// catalogue tokens, whether or not a "No." introduces it. Falls back to a
    /// "No. N" anywhere for movement-first titles ("Prélude No. 24 …, Op. 28").
    nonisolated static func movementNumber(inTitle title: String, work: String) -> String? {
        let hay = normalize(title)
        let workTokens = normalize(work)

        if !workTokens.isEmpty, let end = indexAfter(workTokens, in: hay) {
            var index = end
            if index < hay.count, hay[index] == "no" { index += 1 }
            if index < hay.count, isNumber(hay[index]) { return hay[index] }
        }
        // "Prélude No. 24 in D Minor, Op. 28" — the movement precedes the opus.
        for (word, next) in zip(hay, hay.dropFirst()) where word == "no" && isNumber(next) {
            return next
        }
        return nil
    }

    /// The index just past a contiguous run of `needle` in `haystack`, or nil.
    nonisolated private static func indexAfter(_ needle: [String], in haystack: [String]) -> Int? {
        guard !needle.isEmpty, needle.count <= haystack.count else { return nil }
        for start in 0...(haystack.count - needle.count)
        where Array(haystack[start..<(start + needle.count)]) == needle {
            return start + needle.count
        }
        return nil
    }

    /// True when some catalogue word in the run is immediately followed by a
    /// number or roman numeral — the syntactic core of a catalogue reference.
    nonisolated private static func qualifies(_ run: [String]) -> Bool {
        zip(run, run.dropFirst()).contains { word, next in
            catalogueWords.contains(word) && (isNumber(next) || isRoman(next))
        }
    }

    /// How well `title` matches `reference`, comparing catalogue *pairs* — a
    /// catalogue word bound to its number, like "op 28" and "no 24":
    ///
    /// - 2: the title carries every pair the reference names, so it *is* the
    ///   piece ("…, Op. 28: No. 24 in D Minor", "Prélude No. 24 in D Minor,
    ///   Op. 28").
    /// - 1: the title carries the work-level pair but not the movement, so it's
    ///   a sibling in the same opus ("…, Op. 28: No. 6") or the set's album
    ///   ("24 Préludes, Op. 28").
    /// - 0: unrelated ("Nocturne Op. 9 No. 2").
    ///
    /// Pairing is what keeps the tiers honest. Matching loose numbers would let
    /// the *count* in "24 Préludes, Op. 28" satisfy the "24" of "No. 24", tying
    /// every prelude in the set with the one actually asked for; requiring the
    /// number to sit with its catalogue word ("no 24") separates them. Pairs are
    /// also order-free, so the movement-first titles Apple Music mixes in
    /// ("Prélude No. 24 in D Minor, Op. 28") still reach tier 2.
    nonisolated static func matchTier(title: String, reference: String) -> Int {
        let ref = pairs(in: normalize(reference))
        guard !ref.isEmpty else { return 0 }
        let hay = pairs(in: normalize(title))
        if ref.isSubset(of: hay) { return 2 }
        let work = pairs(in: normalize(workLevel(reference)))
        if !work.isEmpty, work.isSubset(of: hay) { return 1 }
        return 0
    }

    /// The catalogue pairs in `tokens`: each catalogue word joined to the number
    /// that immediately follows it ("op 28", "no 24"). A roman numeral carries a
    /// trailing work number with it, so Haydn's "Hob. XVI 52" stays one pair and
    /// can't match "Hob. XVI 35".
    ///
    /// Requiring the number to *follow* the word is what keeps key names out:
    /// "D" is Schubert's catalogue, but "in D Minor" is followed by a word, so
    /// it yields no pair.
    nonisolated private static func pairs(in tokens: [String]) -> Set<String> {
        var found: Set<String> = []
        for (index, token) in tokens.enumerated() where catalogueWords.contains(token) {
            guard index + 1 < tokens.count else { continue }
            let value = tokens[index + 1]
            guard isNumber(value) || isRoman(value) else { continue }
            var pair = "\(token) \(value)"
            if isRoman(value), index + 2 < tokens.count, isNumber(tokens[index + 2]) {
                pair += " \(tokens[index + 2])"
            }
            found.insert(pair)
        }
        return found
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

}
