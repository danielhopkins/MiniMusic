# IntentBench

Manual harness for exercising the on-device intent parser
(`SearchIntentParser` + `SearchIntent` + `SearchPlanner`) against the **live**
Apple Foundation Model, without launching the app.

Both tools compile the app's real source files directly (no copies), so they
always test the current code and prompt.

## Requirements

- A Mac with **Apple Intelligence enabled** (the model must report available).
- macOS 26+ and the Swift toolchain (`swiftc` on `PATH`).

The model is **nondeterministic**, so these are manual regression checks, not
CI unit tests — that's also why they live here rather than in `MiniMusicTests`.

**Release gate:** do not ship a new release unless `bench.sh` has been run and
passes. `release.sh` prompts for this in its pre-flight step (step 0).

## `bench.sh` — name-survival benchmark

Runs a fixed set of queries (classical composers, popular rock/pop/rap artists,
and deliberately-misspelled "must-fix" cases) N times each and reports how often
the artist/composer name **survives** the parse instead of being mangled
(the "brahms" → "braves" class of bug). A name counts as surviving if it appears
in any name-bearing facet (term/artist/album/song), since we're testing spelling
preservation, not which field it routes to.

```
./bench.sh                    # 5 iterations per query (~3–4 min)
ITERS=8 ./bench.sh            # more iterations for a tighter estimate
MAX_SECONDS=900 ./bench.sh    # raise the watchdog cap
```

A normal call is ~1.5s, so ITERS=5 is ~3–4 min. Live per-query progress prints
to stderr (visible even if you pipe stdout). The on-device model **occasionally
stalls** for minutes on a single call; a watchdog hard-kills the run after
`MAX_SECONDS` (default 600) so it can't hang indefinitely. If you see the
watchdog fire, just re-run.

Groups:
- **composer** / **popular** — names that must be preserved verbatim.
- **must-fix** — real misspellings (`tailor swift`, `metalica`) that must still
  be *corrected*. These guard against "fixing" corruption by disabling spelling
  correction entirely.

Target: 100% on composer/popular, high on must-fix. `metalica` occasionally
slips through uncorrected and is the known soft spot.

After the survival groups, a **routing** phase checks the parsed `categories`.
A request for an artist's music ("pieces by brahms", "kendrick lamar songs")
must resolve to songs — not collapse to the `artist` category, which fetches
only performer entities (the "just the name card, no music" bug). A genuine
"bands like Radiohead" must stay scoped to `artist`. Target: 100%.

## `inspect.sh` — per-query inspector

Prints the parsed facets for specific queries plus the downstream search
consequences the planner + view model would apply (route, catalog fetch limit,
display cap, vibe re-rank).

```
./inspect.sh "brahms piano" "albums by radiohead"
./inspect.sh                 # default query set
```

> The downstream summary in `Inspect.swift` mirrors
> `MusicSearchViewModel.performCatalogSearch` / `allResults`. If those limits or
> caps change, update `downstream(...)` to match.

## Notes

- Each parse uses a **fresh** `SearchIntentParser` so the benchmark measures
  parse quality in isolation. The app itself reuses one long-lived
  `LanguageModelSession`, whose transcript grows across searches — worth keeping
  in mind when reasoning about real-session behavior.
- Build artifacts land in `.build/` (git-ignored).
