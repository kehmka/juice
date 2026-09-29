# Results — 2026-09-28

> **Harness note (2026-09-28, after these sections were written):** the
> harness now keeps every round and reports median + range + spread, and
> declares ties itself (README "What is measured"); a `TOOLCHAIN` pin makes
> `tool/run.sh` refuse a mismatched Flutter. §1–§6 below are from the earlier
> fastest-of-5 harness and are kept as measured; the next Linux run on the
> pinned toolchain will regenerate §2–§4 in the new schema. §7 shows the new
> schema on the Mac (drift allowed, so not a published number).

Machine: 4-core Intel Xeon @ 2.80 GHz (cloud VM), Linux, **release (AOT)**
build, Dart 3.13.4 / Flutter 3.47.5, run headless under Xvfb.
Versions: juice 1.9.1 (this repo), bloc 9.2.1 / flutter_bloc 9.1.1,
flutter_riverpod 3.4.3. Raw data: `results/*.json`. Method: `README.md`.

## 1. Rebuild counts (deterministic)

100 cells; cell 7 updated 10 times.

| variant | builds / update | consumer selector calls / update |
|---|---:|---:|
| **juice · groups** | **1** | **0** |
| juice · JuiceSelector | 1 | 100 |
| bloc · BlocSelector | 1 | 100 |
| riverpod · select | 1 | 101 |
| juice · no groups (default) | 100 | 0 |
| bloc · BlocBuilder (default) | 100 | 0 |
| riverpod · watch (default) | 100 | 0 |

All three frameworks rebuild exactly the changed widget when used
idiomatically. Juice gets there by naming the invalidation once, at the
emitter; selector-based targeting runs a selector in every consumer on every
update. (Juice's group check is also per-widget work — a set intersection —
which is why the frame numbers below are the fair cost comparison.)

## 2. Rebuild frame cost

1000 cells, 300 single-cell updates, one frame each. Engine
`FrameTiming.buildDuration` (build + layout + paint on the UI thread), µs.

| variant | p50 | p90 |
|---|---:|---:|
| **juice · groups** | **4031** | 6240 |
| riverpod · select | 4182 | **6023** |
| juice · JuiceSelector | 4339 | 6434 |
| bloc · BlocSelector | 5047 | 7266 |
| riverpod · watch (default) | 8507 | 11921 |
| bloc · BlocBuilder (default) | 9581 | 12933 |
| juice · no groups (default) | 9599 | 13146 |

The tuned forms land within a few percent of each other at p50, Juice's
groups fastest, with bloc's selector the slowest tuned variant; untargeted
defaults cost roughly 2×. Frame work here is dominated by laying out 1000
children, identical across frameworks — the differences are the targeting
mechanisms themselves. Run-to-run noise on this VM is about ±5%.

## 3. Dispatch cost

No widgets; µs per update; fastest of 5 rounds after a warm-up.

| variant | sequential (await each) | burst (fire all, await last) |
|---|---:|---:|
| riverpod (sync method call) | 0.90 | 2.00 |
| bloc | 2.01 | 1.63 |
| juice · silent logger | 5.90 | 9.70 |
| juice · default logger | 6.50 | 9.68 |

**Juice's dispatch costs ~3× bloc's per event.** That is the price of what a
Juice dispatch does by design: an async executor and a paired telemetry span
(START + END with an execution id) on every execution — section 4 breaks it
down; the fresh use-case instance per event is a minor term. Riverpod's number is a synchronous method call — no event
queue at all. At ~6 µs an event, dispatch is not where a UI spends its frame
budget (one rebuild frame above is ~4000 µs), but it is real, and it is
reported rather than hidden.

### The benchmarks already paid for themselves

The first release run measured Juice's default logger at **12.54 µs**
sequential / **21.41 µs** burst. Two findings, both fixed in 1.9.1:

- `DefaultJuiceLogger` formatted every line — including the state's
  `toString()` — before logger's filter discarded it (which in release is
  every line). It now builds the line only if it will be printed.
- The status emitter put `'${state}'` and `groups.toString()` into its
  telemetry context on every emission, whatever the logger. It now passes
  the objects; loggers that print stringify them themselves.

Result: default-logger dispatch **12.54 → 6.50 µs** sequential (−48%) and
**21.41 → 9.68 µs** burst (−55%), and the default logger now costs about the
same as a silent one. The before run is kept in
`results/timing_before_logger_fixes.json`.

## 4. Where a Juice dispatch's time goes

`lib/breakdown.dart` (`flutter build linux --release -t
lib/breakdown_main.dart`), silent logger, µs per operation, fastest of 5
rounds after a warm-up. Raw data: `results/breakdown.json`.

| layer | kind | µs |
|---|---|---:|
| `send` · `UseCaseBuilder` (fresh use-case instance per event, the default) | real | 4.99 |
| `send` · `StatefulUseCaseBuilder` (one reused instance) | real | 4.65 |
| `StatusEmitter.emitUpdate` (status + group merge + emission log context) | real | 1.81 |
| `StateManager.emit` (raw store: set + broadcast add) | real | 0.04 |
| 3 telemetry context maps + 2 type names, consumed by nothing | synthetic | 1.68 |
| 4 nested awaited async calls (send → dispatcher → executor → execute) | synthetic | 0.79 |

- **The fresh use-case instance is not the cost.** Reusing one instance saves
  **0.34 µs (~7%)** of a send.
- **Telemetry is.** The raw store is 0.04 µs; the emitter around it is 1.81 µs,
  nearly all of it building the emission's log context (a map, the event's
  type name, the message string) and copying the group set. Building the
  three per-event context maps alone costs about as much (1.68 µs) — with a
  silent logger that throws them away.
- **The async executor** (four awaited hops) accounts for ~0.8 µs.

So the ~3× dispatch gap to bloc is mostly Juice's always-on telemetry spans,
then its async path; per-event allocation is a minor term. The lever, if
dispatch cost ever matters, is making telemetry context construction lazy
when no logger consumes it — not changing the use-case lifecycle.

## 5. Reproduction on a second machine — macOS, 2026-09-28

Apple Silicon (12 cores), macOS, **release (AOT)** build, Dart 3.12.2 /
Flutter 3.44.4 (NOT the Linux run's 3.13.4 / 3.47.5 — a toolchain
confound the uniform scaling below argues against, but does not isolate),
real display. Same scenarios, same pinned versions. Raw
data: `results/timing_macos.json`, `results/breakdown_macos.json`. Run
with `tool/run.sh` (it picks the platform).

Rebuild counts: identical to §1 — every tuned form 1 build/update, every
naive form N; the deterministic test passes unchanged.

Dispatch, µs per update (Linux → Mac, ratio):

| variant | sequential | burst |
|---|---:|---:|
| juice · default logger | 6.50 → 3.11 (0.48) | 9.68 → 4.47 (0.46) |
| juice · silent logger | 5.90 → 2.86 (0.49) | 9.70 → 4.23 (0.44) |
| bloc | 2.00 → 0.97 (0.49) | 1.62 → 0.79 (0.48) |
| riverpod | 0.90 → 0.40 (0.45) | 2.00 → 0.61 (0.31) |

Frame cost p50, µs (Linux → Mac): juice·groups 4031 → 834, riverpod·select
4182 → 943, juice·JuiceSelector 4339 → 909, bloc·BlocSelector 5047 → 1163;
naive forms 8507–9599 → 2039–2219.

Breakdown, µs: send·fresh 4.99 → 2.72, send·stateful 4.65 → 2.42,
emitUpdate 1.81 → 0.84, telemetry maps 1.68 → 1.03, 4 hops 0.79 → 0.53,
raw store 0.04 → 0.02.

What this validates:

- **The ordering holds.** Dispatch: Riverpod < bloc < Juice on both
  machines, Juice at ~3.2× bloc sequential on both (3.25 Linux, 3.21 Mac).
  Frame cost: Juice groups fastest tuned form on both; BlocSelector slowest
  tuned form on both, by 25–39%; naive forms ~2.2–2.5× tuned on both.
- **The scaling is uniform.** Nearly every number is 0.45–0.55× on the Mac —
  one machine is about twice as fast and the harness measures the code,
  not the machine. The one outlier (Riverpod burst, 0.31) is a small
  absolute number on both.
- **The near-tie is a tie.** Riverpod·select and Juice·JuiceSelector swap
  places between machines (4182 < 4339 on Linux, 943 > 909 on the Mac);
  both sit within the run-to-run noise of Juice·groups' neighbours. §2's
  "within a few percent" is the right reading; "Juice groups fastest" is
  supported on both machines but by a margin inside the noise against
  Riverpod's select.
- **The breakdown reconciles on the Mac too**: store 0.02 + emitter's extra
  0.82 + hops 0.53 + the two remaining span maps ≈ the 2.72 µs send.

## 6. The phone — iPhone 17 Pro Max, 2026-09-28

The machine Amoli runs on. iOS 26.6, **release (AOT)** build, Dart 3.12.2 /
Flutter 3.44.4, 6 cores, cable-attached, screen awake (Auto-Lock off: iOS
suspends a backgrounded app and the frame benchmark waits on frames that
never come). Raw data: `results/timing_ios.json`, `results/breakdown_ios.json`.
Procedure in README.md ("On a phone").

### Dispatch, µs per update (fastest of 5 rounds)

| variant | sequential | burst |
|---|---:|---:|
| riverpod (sync method call) | 0.28 | 0.42 |
| bloc | 0.76 | 0.61 |
| juice · silent logger | 1.87 | 2.48 |
| juice · default logger | 1.99 | 2.62 |

Juice ÷ bloc, sequential: **2.6×** (3.2× on both desktops). The ordering
Riverpod < bloc < Juice holds on the third machine; the 1.9.1 logger fix
holds too (default vs silent within 6%).

### Where a Juice send goes on the phone, µs

| layer | kind | iPhone | Linux |
|---|---|---:|---:|
| `send` · fresh use-case instance | real | 1.72 | 4.99 |
| `send` · reused instance | real | 1.61 | 4.65 |
| `StatusEmitter.emitUpdate` | real | 0.54 | 1.81 |
| `StateManager.emit` | real | 0.02 | 0.04 |
| 3 telemetry maps + 2 type names | synthetic | 0.69 | 1.68 |
| 4 awaited async hops | synthetic | 0.41 | 0.79 |

Same shape as §4: telemetry context ~40% of a send, the async executor
~25%, the fresh instance ~6%. The layers reconcile (0.02 + 0.52 + 0.41 +
two span maps ≈ 1.72).

### Rebuild counts

Deterministic, identical to §1 — plus the variant added with this run:

| variant | builds / update | selector calls / update |
|---|---:|---:|
| juice · groups | 1 | 0 |
| **juice · JuiceSelector + groups** (idiomatic since 1.8.0) | **1** | **1** |
| juice · JuiceSelector (ungrouped) | 1 | 100 |
| bloc · BlocSelector | 1 | 100 |
| riverpod · select | 1 | 101 |

The grouped selector is the number that justifies keeping the widget: the
group filter runs first, so the selector runs once, in the one cell whose
group fired.

### Frame cost — a measurement artifact, reported as one

`buildDuration` p50 | p90, µs, 1000 cells:

| variant | iPhone | Linux |
|---|---:|---:|
| juice · groups | 3079 \| 3435 | 4031 \| 6240 |
| juice · JuiceSelector + groups | 3783 \| 4353 | — |
| juice · JuiceSelector | 3551 \| 3868 | 4339 \| 6434 |
| bloc · BlocSelector | 3204 \| 4289 | 5047 \| 7266 |
| riverpod · select | 2785 \| 3893 | 4182 \| 6023 |
| juice · no groups (1000 builds) | **2337** \| 2397 | 9599 \| 13146 |
| bloc · BlocBuilder (1000 builds) | **2475** \| 2626 | 9581 \| 12933 |
| riverpod · watch (1000 builds) | **2414** \| 2669 | 8507 \| 11921 |

On both desktops a naive frame costs ~2× a tuned one. **On the phone the
naive forms are FASTER than the tuned ones, for all three frameworks
alike.** A framework-independent inversion is not a framework result. The
reading that fits: a frame rebuilding 1000 cells does enough work to be
scheduled on a performance core at full clock; a one-widget frame runs on
an efficiency core at a low clock and takes longer in wall time (the naive
p90s are tight, the tuned p90s wide — the signature of frequency
variance, not of work). So on this phone the frame numbers are dominated
by laying out 1000 children at a clock the benchmark does not control,
and they do not discriminate between targeting mechanisms. They are kept
here so nobody re-derives the inversion as a finding. What would settle
it: pin the work per frame high enough to stay on a P-core, or measure
CPU time rather than wall time — see the roadmap.

### What the phone validates

- Dispatch ordering and the ~2.6–3.2× Juice-to-bloc ratio: three machines,
  three architectures, one answer.
- The breakdown's shape (telemetry ≫ executor ≫ instance): same on all three.
- The rebuild counts: machine-independent by construction, and now with the
  grouped-selector row.
- Frame cost is only comparable within one machine and one clock regime;
  the desktop tables in §2 remain the fair mechanism comparison.

## 7. The new harness on the Mac — median, range, verdicts (2026-09-28)

Same Mac as §5, Flutter 3.44.4 (`toolchainDrift: true` — the pin is
3.47.5, so these are NOT publishable numbers; they show the schema and
what the harness now says on its own). Every round kept; 5 rounds for
dispatch and breakdown, 3 for frames.

### Dispatch, sequential, µs per update

| variant | median | range | spread |
|---|---:|---:|---:|
| riverpod | 0.40 | 0.38–0.41 | ±3% |
| bloc | 0.98 | 0.95–1.01 | ±3% |
| juice (silent logger) | 2.84 | 2.79–2.96 | ±3% |
| juice (default logger) | 3.08 | 3.05–3.17 | ±2% |

Verdicts (adjacent pairs by median; a tie means the ranges overlap):

- riverpod < bloc: **faster** (59%)
- bloc < juice (silent logger): **faster** (66%)
- juice (silent logger) < juice (default logger): **faster** (8%)

Spreads of 2–3% make every gap here real, including the default-vs-silent
logger gap — 8% on this machine, ranges not overlapping. The 1.9.1 fix
closed most of that gap, not all of it.

### Frame cost, tuned forms, p50 µs (median of 3 rounds)

| variant | median | range | spread |
|---|---:|---:|---:|
| juice · JuiceSelector | 601 | 557–622 | ±5% |
| juice · groups | 616 | 614–752 | ±11% |
| bloc · BlocSelector | 635 | 629–724 | ±8% |
| riverpod · select | 635 | 584–732 | ±12% |
| juice · JuiceSelector + groups | 755 | 685–875 | ±13% |

Verdicts:

- juice · JuiceSelector < juice · groups: **tie** (2%)
- juice · groups < bloc · BlocSelector: **tie** (3%)
- bloc · BlocSelector < riverpod · select: **tie** (0%)
- riverpod · select < juice · JuiceSelector + groups: **tie** (16%)

**Every tuned pair is a tie.** This is the sentence §2 and §5 could only
imply: on the cells scenario the four targeting mechanisms cost the same
per frame within this machine's noise (spreads 5–13% against differences
of 0–3%). The harness now says so itself. The one to watch, not a
finding: `JuiceSelector + groups` has the highest median on the Mac and
the phone both — inside the tie band here, but consistent; the grouped
selector does the group filter AND the selector per widget, and holds a
subscription per cell rather than a `StreamBuilder`. Worth a look when
the second scenario lands.

### Breakdown, µs per op

| layer | kind | median | range | spread |
|---|---|---:|---:|---:|
| stateManager.emit | real | 0.02 | 0.02–0.02 | ±6% |
| statusEmitter.emitUpdate | real | 1.00 | 0.90–1.01 | ±5% |
| telemetry maps (3 per event) | synthetic | 1.05 | 0.99–1.11 | ±6% |
| 4 awaited async hops | synthetic | 0.50 | 0.49–0.54 | ±4% |
| send · StatefulUseCaseBuilder (reused instance) | real | 2.44 | 2.38–2.48 | ±2% |
| send · UseCaseBuilder (fresh instance) | real | 2.71 | 2.69–2.76 | ±1% |

Same shape as §4 and §6, now with the noise attached.

### Learned running it

The frame benchmark awaits engine frames, and the engine delivers frames
only to a visible window. Launched from a background shell the macOS window
sat behind the editor and the run waited at 0% CPU — for 39 minutes the
first time, until it was fronted; it resumed at once. Now: `tool/run.sh`
keeps the app activated until it exits, and a frame that takes more than
5 s prints `BENCH_STALLED` once so the condition is visible in the log.
The same rule produced the phone's Auto-Lock requirement in §6.
