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
    }
}
