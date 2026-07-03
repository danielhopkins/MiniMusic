import Foundation
import FoundationModels

// Name-survival benchmark for the on-device intent parser.
//
// Measures how often the live Foundation Model preserves an artist/composer name
// through `SearchIntentParser.parse` instead of mangling it (the "brahms" →
// "braves" class of bug). Runs each query N times against the real app source
// (`SearchIntentParser`, `SearchIntent`, `SearchPlanner`) and reports a survival
// rate per query and per group.
//
// Requires a Mac with Apple Intelligence enabled; the model is nondeterministic,
// so this is a manual regression check, not a CI unit test. Set ITERS to change
// iterations per query (default 5). See README.md.

struct BenchCase { let query: String; let stems: [String]; let group: String }

func fold(_ s: String) -> String {
    s.folding(options: .diacriticInsensitive, locale: nil).lowercased()
}

/// Writes to stderr, which is unbuffered — so progress is visible live even when
/// stdout is piped (where it would otherwise be block-buffered and look frozen).
/// A normal on-device call takes ~1.5s; if a line sits for minutes the model has
/// stalled (see the watchdog in bench.sh, which caps total wall-clock).
func progress(_ s: String) {
    FileHandle.standardError.write(Data(s.utf8))
}

/// Whole-second formatting for a Duration, e.g. "7s".
func secs(_ d: Duration) -> String { "\(d.components.seconds)s" }

// Each stem is a lowercased/diacritic-folded fragment that must appear somewhere
// in the parsed facets for the name to count as "survived". Stems are lenient
// toward legitimate spelling variants (Rachmaninoff/Rachmaninov) but catch
// corruption to a different word (Braves, Brahm).
let cases: [BenchCase] = [
    // Classical composers — the stress test (out-of-vocabulary surnames).
    .init(query: "brahms piano",                stems: ["brahms"],              group: "composer"),
    .init(query: "chopin nocturne",             stems: ["chopin"],              group: "composer"),
    .init(query: "rachmaninoff piano concerto", stems: ["rachmanin"],           group: "composer"),
    .init(query: "dvorak symphony",             stems: ["dvor"],                group: "composer"),
    .init(query: "shostakovich",                stems: ["shostakovi"],          group: "composer"),
    .init(query: "sibelius violin concerto",    stems: ["sibeliu"],             group: "composer"),
    .init(query: "tchaikovsky",                 stems: ["tchaikov", "chaikov"], group: "composer"),
    .init(query: "debussy piano",               stems: ["debussy"],             group: "composer"),
    .init(query: "grieg piano concerto",        stems: ["grieg"],               group: "composer"),
    .init(query: "mahler symphony",             stems: ["mahler"],              group: "composer"),
    .init(query: "prokofiev piano",             stems: ["prokofiev"],           group: "composer"),
    .init(query: "saint-saens",                 stems: ["saint", "saens"],      group: "composer"),
    // Popular rock / pop / rap artists.
    .init(query: "radiohead",                   stems: ["radiohead"],           group: "popular"),
    .init(query: "beyonce songs",               stems: ["beyonce"],             group: "popular"),
    .init(query: "kendrick lamar",              stems: ["kendrick", "lamar"],   group: "popular"),
    .init(query: "metallica",                   stems: ["metallica"],           group: "popular"),
    .init(query: "nirvana songs",               stems: ["nirvana"],             group: "popular"),
    .init(query: "the weeknd",                  stems: ["weeknd"],              group: "popular"),
    .init(query: "led zeppelin",                stems: ["zeppelin"],            group: "popular"),
    .init(query: "tyler the creator",           stems: ["tyler"],               group: "popular"),
    .init(query: "doja cat",                    stems: ["doja"],                group: "popular"),
    .init(query: "sza songs",                   stems: ["sza"],                 group: "popular"),
    .init(query: "foo fighters",                stems: ["foo fighter"],         group: "popular"),
    .init(query: "arctic monkeys",              stems: ["arctic monkey"],       group: "popular"),
    // Guard cases: real misspellings that SHOULD still be corrected. If a prompt
    // fix works by disabling correction entirely, these regress and expose it.
    .init(query: "tailor swift",                stems: ["taylor"],              group: "must-fix"),
    .init(query: "beyonse songs",               stems: ["beyonce"],             group: "must-fix"),
    .init(query: "metalica",                    stems: ["metallica"],           group: "must-fix"),
    .init(query: "radiohed",                    stems: ["radiohead"],           group: "must-fix"),
]

/// What a query should route to. `wantsMusic` = the user asked for an artist's
/// music, so the search must return songs/albums — NOT be scoped to the "artist"
/// category (which fetches only performer entities, the "brahms → just the name
/// card" bug). `wantsArtistList` = the user genuinely wants performers, so the
/// "artist" category is correct.
enum RouteWant { case wantsMusic, wantsArtistList }

struct RouteCase { let query: String; let want: RouteWant }

/// Passes when the parsed categories match the intent. The failure we care about
/// is a music request collapsing to an artist-only search.
func routePasses(_ facets: SearchFacets, _ want: RouteWant) -> Bool {
    switch want {
    case .wantsMusic:      return facets.categories != [.artist]
    case .wantsArtistList: return facets.categories == [.artist]
    }
}

// Routing regressions the name-survival benchmark can't see: a named artist's
// music request must not collapse to an artist-only search.
let routeCases: [RouteCase] = [
    .init(query: "pieces by brahms",     want: .wantsMusic),
    .init(query: "brahms music",         want: .wantsMusic),
    .init(query: "works by chopin",      want: .wantsMusic),
    .init(query: "kendrick lamar songs", want: .wantsMusic),
    .init(query: "music by radiohead",   want: .wantsMusic),
    .init(query: "drake songs",          want: .wantsMusic),
    .init(query: "taylor swift music",   want: .wantsMusic),
    .init(query: "beyonce tracks",       want: .wantsMusic),
    // The genuine artist-list case must stay scoped to artists.
    .init(query: "bands like radiohead", want: .wantsArtistList),
]

@main
struct Benchmark {
    static func main() async {
        let iters = Int(ProcessInfo.processInfo.environment["ITERS"] ?? "5") ?? 5
        print("model available: \(SearchIntentParser().isAvailable)   iters/query: \(iters)\n")

        var groupOK: [String: Int] = [:]
        var groupTotal: [String: Int] = [:]

        let clock = ContinuousClock()
        let started = clock.now
        for (i, c) in cases.enumerated() {
            progress("[\(i + 1)/\(cases.count)] \(c.query) … ")
            let caseStart = clock.now
            var preserved = 0, mangled = 0, nils = 0
            var bad: [String] = []
            for _ in 0..<iters {
                // Fresh session per call: isolate parse quality from the transcript
                // buildup that a single long-lived session would accumulate.
                if let intent = await SearchIntentParser().parse(c.query) {
                    let f = intent.facets
                    // The name may land in any name-bearing facet (term/artist/
                    // album/song). We're testing spelling preservation, not which
                    // field it routes to, so search across all of them.
                    let haystack = fold("\(f.term) \(f.artist) \(f.album) \(f.song)")
                    if c.stems.contains(where: { haystack.contains(fold($0)) }) {
                        preserved += 1
                    } else {
                        mangled += 1
                        bad.append("term=\"\(f.term)\" artist=\"\(f.artist)\"")
                    }
                } else {
                    nils += 1
                }
            }
            progress("\(preserved)/\(iters) in \(secs(caseStart.duration(to: clock.now)))\n")
            groupOK[c.group, default: 0] += preserved
            groupTotal[c.group, default: 0] += iters
            let flag = mangled > 0 ? "❌" : "✓ "
            let nilNote = nils > 0 ? "  nil:\(nils)" : ""
            let badNote = bad.isEmpty ? "" : "   mangled→ \(Set(bad).sorted().joined(separator: ", "))"
            print("\(flag) \(preserved)/\(iters)  [\(c.group)] \"\(c.query)\"\(nilNote)\(badNote)")
        }

        print("\n── group survival ──")
        for g in groupTotal.keys.sorted() {
            let ok = groupOK[g] ?? 0, tot = groupTotal[g] ?? 1
            print("  \(g): \(ok)/\(tot)  (\(Int(Double(ok) / Double(tot) * 100))%)")
        }
        let ok = groupOK.values.reduce(0, +), tot = groupTotal.values.reduce(0, +)
        print("  OVERALL: \(ok)/\(tot)  (\(Int(Double(ok) / Double(tot) * 100))%)   in \(secs(started.duration(to: clock.now)))")

        // ── Routing phase ────────────────────────────────────────────────
        print("\n── routing (categories) ──")
        var routeOK = 0, routeTot = 0
        for (i, rc) in routeCases.enumerated() {
            progress("[route \(i + 1)/\(routeCases.count)] \(rc.query) … ")
            let rStart = clock.now
            var pass = 0
            var seen: [String] = []
            for _ in 0..<iters {
                if let intent = await SearchIntentParser().parse(rc.query) {
                    let cats = intent.facets.categories.map(\.rawValue).sorted().joined(separator: ",")
                    seen.append(cats.isEmpty ? "∅" : cats)
                    if routePasses(intent.facets, rc.want) { pass += 1 }
                }
            }
            routeOK += pass; routeTot += iters
            progress("\(pass)/\(iters) in \(secs(rStart.duration(to: clock.now)))\n")
            let flag = pass == iters ? "✓ " : "❌"
            let want = rc.want == .wantsMusic ? "music" : "artist-list"
            let counts = Dictionary(grouping: seen, by: { $0 }).mapValues(\.count)
                .sorted { $0.key < $1.key }.map { "\($0.key)×\($0.value)" }.joined(separator: " ")
            print("\(flag) \(pass)/\(iters)  want=\(want)  \"\(rc.query)\"   categories: \(counts)")
        }
        print("  ROUTING: \(routeOK)/\(routeTot)  (\(Int(Double(routeOK) / Double(routeTot) * 100))%)")
    }
}
