# Juice benchmarks — Juice vs bloc vs Riverpod

**Latest results: [RESULTS.md](RESULTS.md).**

Measured numbers for the claims Juice makes, on one shared scenario, with each
framework in its **idiomatic ("tuned")** form and its **default ("naive")**
form. Not a published package; kept outside `packages/` so bloc and Riverpod
never enter the Juice family's dependency graph or CI.

Versions measured (pinned in `pubspec.yaml`): juice (this repo, path),
bloc 9.2.1 / flutter_bloc 9.1.1, flutter_riverpod 3.4.3.

## The scenario

`N` cell widgets, each showing one `int` of shared state (a `List<int>`); an
update sets one cell. Every framework holds the list immutably and replaces it
on update.

| variant | how the rebuild is targeted |
|---|---|
| juice · groups | the use case names the changed cell's group; each widget filters by set intersection |
| juice · JuiceSelector + groups | group filter first (denyRebuild), then consumer-side selector + `==` — the idiomatic form since 1.8.0 |
| juice · JuiceSelector | consumer-side selector + `==` (no groups) |
| juice · no groups | the default: `rebuildAlways` broadcast |
| bloc · BlocSelector | consumer-side selector + `==` |
| bloc · BlocBuilder | the default: no filter |
| riverpod · select | consumer-side `select` + `==` |
| riverpod · watch | the default: watch the whole list |

Bloc is used with events (a `Bloc`, not a `Cubit`) so dispatch is comparable
to Juice's event → use case path. Riverpod has no event queue: an update is a
synchronous notifier method call — that difference is part of what the
dispatch numbers show, not something to normalize away.

## The second scenario: wide

`lib/scenarios/wide.dart`, built to stress what groups do NOT help with:
N cells plus a header showing the sum over every cell; one update sets a
run of K = N/20 consecutive cells, so K cells and the header change every
update. Tuned forms build K+1 per update, naive N+1 (pinned by
`test/rebuild_counts_wide_test.dart`). The timing app reports it as
`framesWide` / `frameWideComparisons`. RESULTS §10.

## What is measured

1. **Rebuild counts** (`test/rebuild_counts_test.dart`,
   `test/rebuild_counts_wide_test.dart`; `flutter test`; **run in CI** as the
   "Benchmark Rebuild Counts" step, so the harness cannot rot silently) —
   100 cells, cell 7 updated 10 times: widgets built per update, and
   consumer-side selector calls per update. **Deterministic**: independent of
   machine and build mode, and pinned by the test (tuned = 1 build/update,
   naive = 100).
2. **Dispatch cost** (`lib/dispatch.dart`, release build) — µs per update
   with no widgets: `sequential` (await each) and `burst` (fire all, await
   the last). Juice is reported with its **default logger** and with a
   **silent logger**, because its default telemetry formatting is a
   measurable per-emission cost of its own.
3. **Rebuild frame cost** (`lib/main.dart`, release build) — 1000 cells, 300
   single-cell updates, one frame each; p50/p90 of the engine's
   `FrameTiming.buildDuration` (UI thread: build + layout + paint). Raster is
   excluded: under a virtual display it would time a software rasterizer.

4. **Dispatch breakdown** (`lib/breakdown.dart`, release build) — where a
   Juice `send` spends its time: the real layers (raw store, status emitter,
   full send with a reused vs a fresh use-case instance) timed directly, plus
   two labelled synthetic layers (the telemetry maps alone, the async hop
   depth alone).

Each timing benchmark runs a warm-up round, then keeps **every** one of 5
rounds per variant (3 for the frame benchmark) and reports the **median with
its range** (`min`, `max`, `spread` = half-range over median) plus the raw
rounds. The report also carries **verdicts**: variants measuring the same
thing are sorted by median, and each adjacent pair is a `tie` when their
ranges overlap or `faster` by a percentage when they do not
(`dispatchComparisons`, `frameComparisons`). A difference inside the spread
is declared a tie by the harness — not left to the reader.

## Clock pin, clock probe, phases

Frame timings carry three extra fields. `clockProbeMicros` is a fixed piece
of CPU work timed inside every measured frame — a direct read of the clock
the frame ran at (its median is subtracted from the raw build duration).
`rasterMicrosP50`, `totalSpanMicrosP50`, `vsyncOverheadMicrosP50` and
`uiThreadMicrosP50` say where a frame's time sits. And on phones the frame
phase runs with a **busy isolate pinning the clock** (`clockPinned: true`),
because dynamic frequency scaling otherwise runs the whole SoC slower for a
light frame than a heavy one — every phase, raster included — and a
one-widget frame measures slower than a 1000-widget frame (RESULTS §8).
`--dart-define=BENCH_NO_PIN=true` disables it; the report says which.

## Toolchain pin

`TOOLCHAIN` holds the Flutter version the published numbers were compiled
with. `tool/run.sh` refuses to run on any other version, because timings
compiled by different Dart versions are not comparable. To run anyway (a
local look, never for RESULTS.md) set `JUICE_BENCH_ALLOW_DRIFT=1`; the
results then carry `"toolchainDrift": true` and the actual `"flutter"`
version. Phone builds by hand should pass the same defines:
`--dart-define=BENCH_FLUTTER=<version> --dart-define=BENCH_TOOLCHAIN_DRIFT=<bool>`.

## Running

```bash
benchmarks/tool/run.sh
```

Needs Flutter, the Linux desktop toolchain (clang, cmake, ninja, pkg-config,
libgtk-3-dev) and `xvfb-run`. Writes `results/rebuild_counts.json`,
`results/timing.json` and `results/breakdown.json` (the timing files record
the Dart version and CPU count). Timing numbers are only comparable between
runs on the same machine.

## On a phone

The scenarios run unchanged; only the transport differs. `ios/` and `macos/`
runners are checked in (`flutter create --platforms=…` output, signing team
set in `ios/`). Cable-attach the phone, unlock it, set Auto-Lock to Never
for the run (a suspended app never gets frames), then:

```bash
flutter build ios --release
xcrun devicectl device install app --device <udid> build/ios/iphoneos/Runner.app
xcrun devicectl device process launch --console --terminate-existing \
  --device <udid> com.example.juiceBenchmarks | tee run.log
sed -n '/BENCH_JSON_BEGIN/,/BENCH_JSON_END/p' run.log | sed '1d;$d' > results/timing_ios.json
```

and again with `-t lib/breakdown_main.dart` for `breakdown_ios.json`.

**The frame benchmark needs a visible window, on every platform.** The engine
delivers frames only to a window that is on screen: an occluded macOS window
or a backgrounded phone app gets none, and the run sits at 0% CPU until it is
fronted (it resumes by itself when it is). On macOS `tool/run.sh` keeps the
app activated until it exits — expect it to take focus for the few minutes
the frame phase runs. A frame that takes more than 5 s prints
`BENCH_STALLED` once, so a stall is diagnosable from the log rather than
silent; that variant's timing is then suspect. The app
prints `BENCH_PROGRESS` lines per phase and also writes the JSON to its
Documents dir (copy out with `devicectl device copy from --domain-type
appDataContainer --domain-identifier com.example.juiceBenchmarks --source
Documents/bench_timing.json`). Two things learned the hard way: `print` on
iOS goes to os_log, not the captured stdout, and a wireless tunnel drops —
use `stdout` and a cable. Read the phone's frame numbers with RESULTS §6 in
hand.

## Reading the results honestly

- All three frameworks reach **1 build per update** when used idiomatically.
  The difference is *where* the targeting lives: Juice names the invalidation
  once, at the emitter; selector-based approaches run a selector in every
  consumer on every update (see the selector-calls column).
- Juice's group filter is also per-widget work (a set intersection per
  subscribed widget per emission), so "no selector calls" is not "no work" —
  the frame-cost numbers are the fair comparison of the two.
- Headless Linux under Xvfb is not a phone. Relative ordering is the result;
  absolute microseconds are this machine's.
