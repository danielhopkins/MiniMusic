#if DEBUG
import Foundation
import MusicKit

/// Debug-only harness that runs a real search and prints what came back.
///
/// `Tools/IntentBench` can exercise the parser and planner from a plain binary,
/// but MusicKit can't be reached that way: an Apple Music grant is tied to a
/// bundle identifier, so a bare CLI aborts in TCC no matter how it's signed.
/// Running inside the signed, already-authorized app is what makes the fetch and
/// ranking observable — the part `inspect.sh` is blind to.
///
/// It drives `MusicSearchViewModel` exactly as typing does, so what it prints is
/// the production path, not a reimplementation of it.
///
///   MINIMUSIC_PROBE="chopin op 28 no 24" \
///     ~/Library/Developer/Xcode/DerivedData/MiniMusic-*/Build/Products/Debug/MiniMusic.app/Contents/MacOS/MiniMusic
enum CatalogueProbe {

    /// The query to probe, or nil for a normal launch.
    static var requestedQuery: String? {
        ProcessInfo.processInfo.environment["MINIMUSIC_PROBE"]
    }

    /// Station queries to probe, or nil for a normal launch. Accepted either as
    /// `MINIMUSIC_STATION_PROBE="a|b"` or as launch arguments
    /// `--station-probe a b`, so the probe can be started through `open`, which
    /// is the only way it gets a TCC identity that MusicKit will accept.
    static var requestedStationQueries: [String]? {
        if let env = ProcessInfo.processInfo.environment["MINIMUSIC_STATION_PROBE"] {
            return env.split(separator: "|").map { $0.trimmingCharacters(in: .whitespaces) }
        }
        let args = ProcessInfo.processInfo.arguments
        guard let flag = args.firstIndex(of: "--station-probe") else { return nil }
        let queries = Array(args[args.index(after: flag)...])
        return queries.isEmpty ? nil : queries
    }

    /// Where the station probe writes its report. `open` detaches the app from
    /// the terminal, so stdout goes nowhere — a file is how the result gets back.
    private static let stationReportPath = NSTemporaryDirectory() + "minimusic-station-probe.txt"

    /// Searches the catalog for stations matching each query and prints what
    /// came back, including whether each is a live broadcast and who provides
    /// it. Answers whether terrestrial call signs ("KBCO") are reachable at all.
    ///
    ///   MINIMUSIC_STATION_PROBE="kbco|cpr classical" \
    ///     ~/Library/Developer/Xcode/DerivedData/MiniMusic-*/Build/Products/Debug/MiniMusic.app/Contents/MacOS/MiniMusic
    static func runStations(queries: [String]) async {
        var report = ""
        func emit(_ line: String) {
            print(line)
            report += line + "\n"
        }

        // MusicKit refuses catalog requests until the Apple Music grant is
        // resolved for this launch, so ask before searching.
        let status = await MusicAuthorization.request()
        emit("authorization: \(status)")

        for query in queries {
            emit("── station probe: \"\(query)\"")
            do {
                var request = MusicCatalogSearchRequest(term: query, types: [Station.self])
                request.limit = 25
                let response = try await request.response()
                emit("   stations: \(response.stations.count)")
                for station in response.stations {
                    emit(String(format: "     %@  live=%@  provider=%@  id=%@",
                                station.name,
                                station.isLive ? "YES" : "no",
                                station.stationProviderName ?? "—",
                                station.id.rawValue))
                    if let note = station.editorialNotes?.short ?? station.editorialNotes?.standard {
                        emit("        \(note)")
                    }
                }
                if response.stations.isEmpty { emit("   ⚠️ no stations") }
            } catch {
                emit("   ERROR: \(error)")
            }
        }

        try? report.write(toFile: stationReportPath, atomically: true, encoding: .utf8)
        exit(0)
    }

    /// Queries to run through the whole search pipeline, or nil for a normal
    /// launch. Unlike `MINIMUSIC_PROBE`, this reports every result's kind, so it
    /// can show which categories a query actually routed to.
    static var requestedPipelineQueries: [String]? {
        let args = ProcessInfo.processInfo.arguments
        guard let flag = args.firstIndex(of: "--search-probe") else { return nil }
        let queries = Array(args[args.index(after: flag)...])
        return queries.isEmpty ? nil : queries
    }

    /// Drives `MusicSearchViewModel` exactly as typing does and reports what each
    /// query resolved to, so routing (did "cpr radio" scope to stations?) and
    /// results can be checked together.
    static func runPipeline(queries: [String], viewModel: MusicSearchViewModel) async {
        var report = ""
        func emit(_ line: String) {
            print(line)
            report += line + "\n"
        }

        _ = await MusicAuthorization.request()

        for query in queries {
            emit("── pipeline probe: \"\(query)\"")
            viewModel.searchQuery = query
            try? await Task.sleep(for: .milliseconds(900))
            for _ in 0..<100 where viewModel.isLoading {
                try? await Task.sleep(for: .milliseconds(100))
            }
            let results = viewModel.allResults
            emit("   results: \(results.count)  (intelligence: \(viewModel.usedIntelligence))")
            for item in results.prefix(12) {
                emit("     [\(item.sectionName)] \(item.title) — \(item.subtitle)")
            }
            if results.isEmpty { emit("   ⚠️ no results") }
        }

        try? report.write(toFile: stationReportPath, atomically: true, encoding: .utf8)
        exit(0)
    }

    /// Station ID and duration for the live-metadata monitor, or nil.
    static var requestedLiveMonitor: (id: String, seconds: Int)? {
        let args = ProcessInfo.processInfo.arguments
        guard let flag = args.firstIndex(of: "--live-monitor"),
              args.count > flag + 1 else { return nil }
        let id = args[flag + 1]
        let seconds = args.count > flag + 2 ? Int(args[flag + 2]) ?? 60 : 60
        return (id, seconds)
    }

    /// Plays a live station and watches what the queue actually exposes over
    /// time: every `objectWillChange` publish alongside a once-per-second poll of
    /// the current entry. Whether the track metadata arrives at all, and whether
    /// a publish accompanies it, is what decides how now-playing has to observe.
    static func runLiveMonitor(id: String, seconds: Int) async {
        var report = ""
        func emit(_ line: String) {
            print(line)
            report += line + "\n"
        }

        _ = await MusicAuthorization.request()
        let player = ApplicationMusicPlayer.shared

        do {
            let request = MusicCatalogResourceRequest<Station>(
                matching: \.id, equalTo: MusicItemID(id))
            guard let station = try await request.response().items.first else {
                emit("⚠️ station not found"); exit(1)
            }
            emit("station: \(station.name)  live=\(station.isLive)")
            player.queue = [station]
            try await player.play()
        } catch {
            emit("ERROR: \(error)"); exit(1)
        }

        let start = Date()
        func stamp() -> String { String(format: "%5.1fs", Date().timeIntervalSince(start)) }

        var publishes = 0
        let cancellable = player.queue.objectWillChange.sink { _ in
            publishes += 1
            print("\(stamp())  ⚡️ objectWillChange #\(publishes)")
        }

        // Snapshot the entry each second; log only when something changed, so the
        // report shows transitions rather than a wall of identical rows.
        var last = ""
        var publishesAtLast = 0
        for _ in 0..<seconds {
            try? await Task.sleep(for: .seconds(1))
            let entry = player.queue.currentEntry
            let itemKind: String
            switch entry?.item {
            case .song(let s): itemKind = "song(\(s.title))"
            case .musicVideo: itemKind = "musicVideo"
            case .none: itemKind = "nil"
            @unknown default: itemKind = "unknown"
            }
            let snapshot = """
                id=\(entry?.id ?? "—")  title=\(entry?.title ?? "—")  \
                subtitle=\(entry?.subtitle ?? "—")  artwork=\(entry?.artwork != nil)  \
                item=\(itemKind)
                """
            if snapshot != last {
                emit("\(stamp())  [publishes: \(publishes), +\(publishes - publishesAtLast)]")
                emit("          \(snapshot)")
                last = snapshot
                publishesAtLast = publishes
            }
        }
        emit("total publishes: \(publishes)")
        cancellable.cancel()
        player.pause()

        try? report.write(toFile: stationReportPath, atomically: true, encoding: .utf8)
        exit(0)
    }

    /// Runs `query` through `viewModel` and prints each result with the
    /// catalogue tier it scored, then exits. Tier 2 is the piece asked for,
    /// 1 a sibling in the same opus, 0 unrelated — so a correct search shows
    /// tier 2 at the top.
    static func run(query: String, viewModel: MusicSearchViewModel) async {
        let reference = CatalogueReference.extract(from: query) ?? ""
        print("── probe: \"\(query)\"")
        print("   reference: \"\(reference)\"")

        viewModel.searchQuery = query

        // The view model debounces at 500ms, then fetches; wait for it to settle
        // rather than racing it.
        try? await Task.sleep(for: .milliseconds(900))
        for _ in 0..<100 where viewModel.isLoading {
            try? await Task.sleep(for: .milliseconds(100))
        }

        let results = viewModel.allResults
        print("   results: \(results.count)  (intelligence: \(viewModel.usedIntelligence))")
        guard !results.isEmpty else {
            print("   ⚠️ no results")
            exit(1)
        }

        func isMatch(_ item: SearchResultItem) -> Bool {
            !reference.isEmpty && CatalogueReference.isMovement(title: item.title, of: reference)
        }

        for (index, item) in results.enumerated() {
            let tier = reference.isEmpty
                ? 0
                : CatalogueReference.matchTier(title: item.title, reference: reference)
            print(String(format: "   %2d. [tier %d] %@ — %@ %@",
                         index + 1, tier, item.title, item.subtitle,
                         isMatch(item) ? "◀ MATCH" : ""))
        }

        let matches = results.filter(isMatch)
        print("   matches: \(matches.count)  first at: \(results.firstIndex(where: isMatch).map { $0 + 1 } ?? -1)")

        if !reference.isEmpty {
            let artist = query.replacingOccurrences(of: reference, with: "")
                .trimmingCharacters(in: .whitespaces)
            await probeWorkResolution(reference: reference, artist: artist)
        }
        exit(matches.isEmpty ? 1 : 0)
    }

    /// Traces `MusicSearchViewModel.surfaceCatalogueWork` step by step: which
    /// albums the work search returns, which one gets picked, and what its tracks
    /// score. This is the fallback that's supposed to guarantee the referenced
    /// piece appears when Apple's lexical search omits it.
    private static func probeWorkResolution(reference: String, artist: String) async {
        let work = CatalogueReference.workLevel(reference)
        let searchTerm = artist.isEmpty ? reference : "\(artist) \(work)"
        print("── work resolution: term=\"\(searchTerm)\"  work=\"\(work)\"")
        do {
            var request = MusicCatalogSearchRequest(term: searchTerm, types: [Album.self])
            request.limit = 10
            let response = try await request.response()
            print("   albums: \(response.albums.count)")
            for album in response.albums {
                let tier = CatalogueReference.matchTier(title: album.title, reference: work)
                print("     [tier \(tier)] \(album.title) — \(album.artistName)")
            }

            let candidates = CatalogueReference.ranked(
                Array(response.albums), reference: work, title: \.title)
            guard let album = candidates.first,
                  CatalogueReference.matchTier(title: album.title, reference: work) > 0
            else {
                print("   ⚠️ no album title carries \"\(work)\" → surfaceCatalogueWork bails")
                return
            }
            print("   chosen: \(album.title)")

            let detailed = try await album.with([.tracks])
            let tracks = detailed.tracks ?? []
            print("   tracks: \(tracks.count)")
            for track in tracks {
                guard case .song(let song) = track else { continue }
                let tier = CatalogueReference.matchTier(title: song.title, reference: reference)
                print("     [tier \(tier)] \(song.title)")
            }
        } catch {
            print("   ERROR: \(error)")
        }
    }
}
#endif
