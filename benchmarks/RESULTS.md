# Results — 2026-09-28

## Where it stands

The current number for each claim, the machine and section it comes from,
and its caveat. Everything below this table is the lab record, in the
order it was measured; later sections supersede earlier ones where they
say so. Versions: juice 1.9.1 for §1–§8, **1.10.0** for §9–§10 (the knob
is the only difference); bloc 9.2.1 / flutter_bloc 9.1.1; flutter_riverpod
3.4.3. Method and the tie rule: `README.md`.

| claim | number | where | caveat |
|---|---|---|---|
| **Rebuild counts** | every tuned form 1 build / update; Juice groups AND Riverpod family 0 selector calls, BlocSelector and JuiceSelector 100, Riverpod select 101; naive forms 100 | §1 (cells), §10 (wide: tuned K+1, naive N+1) | none — deterministic, machine-independent, pinned by test and run in CI |
| **Frame cost, cells** | the tuned forms of all three frameworks **tie** within machine noise, Riverpod's provider-per-cell family included (family vs groups: 8% on the Mac, 2% on the pinned phone); untargeted defaults ~2× (Linux 4031 vs 9581 µs p50; phone pinned 373–429 vs 1050–1231 µs) | §2 (Linux), §7 (Mac, ties declared), §8 (phone, clock pinned), §11 (family, Mac + phone) | Linux is old-schema fastest-of-5; Mac is a toolchain-drift run; phone numbers are valid only with the clock pinned; family not on Linux |
| **Frame cost, wide** (built to hurt groups) | against selector forms groups hold (phone: JuiceSelector+groups 648, groups 666, BlocSelector 688, Riverpod select 792 µs p50; naive 1330–1498); against Riverpod's **family** form the Mac and the phone point opposite ways raw (family 16% under groups on the Mac; groups 9% under family on the phone) and **both tie probe-normalized** — a tie band, no winner | §10 (phone, pinned), §11 (family, Mac + phone) | drift toolchain both; the family variant's probe ran high on the phone (434 vs 384–407) so its raw number is the suspect one |
| **Dispatch** | Juice ~3× bloc per event on desktops, 2.6× on the phone (1.87 vs 0.76 µs); ~1.5× with the chatter not built — which is the DEFAULT in release from 1.10.0 (the default logger declares it keeps nothing there, §13; Mac 2.72 → 1.82 µs with nothing configured). Juice's burst-slower-than-sequential number is the 20,000-deep in-flight chain, not the per-event path: at 2,000 in flight burst is cheaper (§12) | §3 (Linux), §6 (phone), §9 (knob), §12 (burst), §13 (default) | by design: async executor + paired telemetry span; at ~2–6 µs an event, dispatch is not where a frame budget goes; four awaited hops for one structural await is a candidate (§12) |
| **Where a send goes** | telemetry context ~40%, async executor ~25%, fresh use-case instance ~6% | §4 (Linux), §6 (phone) | the 1.9.1 fixes removed the eager stringification; the knob removes the rest of the chatter |
| **The knob, and the default** | a logger declares what it keeps and nothing below it is built; the default logger keeps nothing in release, so the saving is the default (§13). By hand, `JuiceLoggerConfig.minLevel = Level.warning` saves about a third of a send: Mac 2.79 → 1.90 µs (32%), phone 1.73 → 1.12 µs (35%) | §9, §13 | ranges do not overlap; §13 is Mac only so far |

Superseded and kept as measured: §5's and §6's frame tables (the phone's
inversion, explained and fixed in §8); §2–§4's fastest-of-5 schema (the
next Linux run on the pinned toolchain regenerates them as median + range).
Not yet measured anywhere: a parent-rebuild scenario (roadmap item J).
Riverpod's family form (one provider per cell — the other idiomatic
Riverpod, and the source-side counterpart of groups) was added
2026-09-29; its counts are in §1 and §10, its frame cost is in §11: within
a few percent of groups either way on both machines, a tie once the clock
is accounted for.

---

## The lab record

> **Harness note (2026-09-28, after §1–§6 were written):** the harness now
> keeps every round and reports median + range + spread, and declares ties
> itself (README "What is measured"); a `TOOLCHAIN` pin makes `tool/run.sh`
> refuse a mismatched Flutter. §1–§6 are from the earlier fastest-of-5
> harness and are kept as measured. §7 onward use the new schema.

Machine for §1–§4: 4-core Intel Xeon @ 2.80 GHz (cloud VM), Linux,
**release (AOT)** build, Dart 3.13.4 / Flutter 3.47.5, run headless under
Xvfb. Raw data: `results/*.json`. Method: `README.md`.

## 1. Rebuild counts (deterministic)

100 cells; cell 7 updated 10 times.

| variant | builds / update | consumer selector calls / update |
|---|---:|---:|
| **juice · groups** | **1** | **0** |
| juice · JuiceSelector | 1 | 100 |
| bloc · BlocSelector | 1 | 100 |
| **riverpod · family** | **1** | **0** |
| riverpod · select | 1 | 101 |
| juice · no groups (default) | 100 | 0 |
| bloc · BlocBuilder (default) | 100 | 0 |
| riverpod · watch (default) | 100 | 0 |

All three frameworks rebuild exactly the changed widget when used
idiomatically. Juice gets there by naming the invalidation once, at the
emitter; selector-based targeting runs a selector in every consumer on every
update. **Riverpod's family form (added 2026-09-29) matches Juice's counts
exactly** — one provider per cell puts the targeting in the provider graph,
so an update touches one provider and no selector runs. "0 selector calls"
is therefore not unique to groups; it is what any source-side targeting
gives, and the frame numbers are where the two source-side forms differ,
if they do. (Juice's group check is also per-widget work — a set intersection —
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

## 5. Reproduction on a second machine — macOS, 2026-09-28 (frame table superseded by §7)

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

## 6. The phone — iPhone 17 Pro Max, 2026-09-28 (frame table superseded by §8)

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
it: pin the clock — done in §8, which supersedes this table.

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

## 8. The phone's frame inversion, explained and fixed (2026-09-28)

§6 reported that on the iPhone the naive 1000-rebuild forms measured
FASTER than the tuned one-rebuild forms, for all three frameworks alike,
and called it an artifact. This section is the experiment that found the
cause and the harness change that removes it. Same phone, same build
settings as §6 (Flutter 3.44.4, drift allowed).

### Step 1 — a clock probe inside every frame

A fixed piece of CPU work timed in a transient frame callback (on the UI
thread, just before build), reported per variant as `clockProbeMicros`
and subtracted from the raw build duration. If light frames run at a
lower clock, the probe takes longer in the tuned variants.

It did: naive variants 652–734 µs, tuned variants 775–1012 µs — light
frames ran 20–35% slower. Even the Mac showed it (534–579 vs 599–618).
Hypothesis confirmed. But normalizing by the probe did **not** restore the
desktop ordering (tuned still ~1.1–1.3× naive after normalization).

### Step 2 — every phase, not just build

Recording the engine's raster duration, total span and vsync overhead
alongside a UI-thread stopwatch of our own showed the tuned variants
slower in **every** phase — raster included: ~1750 µs against ~775 µs for
the naive forms, on a different thread, drawing the same picture. Only one
thing does that: dynamic frequency scaling of the whole SoC. A light frame
lets the chip idle down, and every thread pays; a short UI-thread probe
sees only part of it (its own burst partly wakes the clock).

### Step 3 — pin the clock

A busy isolate for the duration of the frame phase (one core, which the UI
and raster threads do not use) keeps the frequency up for every variant
alike. `clockPinned: true` in the report; default on for phones, off on
desktop, `--dart-define=BENCH_NO_PIN=true` to disable.

p50 build µs (probe subtracted), median of 3 rounds:

| variant | probe µs | build p50 | range | raster p50 | builds/update |
|---|---:|---:|---:|---:|---:|
| juice · JuiceSelector + groups | 389 | 372 | 371–377 | 459 | 1 |
| juice · JuiceSelector | 389 | 373 | 371–374 | 450 | 1 |
| riverpod · select | 384 | 376 | 376–378 | 452 | 1 |
| juice · groups | 389 | 377 | 371–380 | 458 | 1 |
| bloc · BlocSelector | 384 | 421 | 414–422 | 448 | 1 |
| riverpod · watch | 389 | 1029 | 1026–1031 | 456 | 1000 |
| juice · no groups | 389 | 1090 | 1076–1096 | 470 | 1000 |
| bloc · BlocBuilder | 389 | 1185 | 1176–1188 | 463 | 1000 |

Verdicts among the tuned forms:

- juice · JuiceSelector + groups < juice · JuiceSelector: **tie** (0%)
- juice · JuiceSelector < riverpod · select: **faster** (1%)
- riverpod · select < juice · groups: **tie** (0%)
- juice · groups < bloc · BlocSelector: **faster** (10%)

The probe is flat (384–389 µs, every variant), raster is flat (~450–470),
and the ordering matches both desktops: **a 1000-widget frame costs ~2.8×
a one-widget frame on the phone**, the tuned forms tie with each other,
and `BlocSelector` sits 10% behind. Absolute numbers with the clock up: a
one-widget frame ~0.4 ms, a 1000-widget frame ~1.1 ms of build on an
iPhone 17 Pro Max.

### What this means for reading phone numbers

- Wall-clock frame times on a phone are not comparable across variants of
  different weight unless the clock is held constant. The harness now
  holds it. §6's frame table is superseded by the one above; its dispatch
  and breakdown tables stand (those phases run the CPU flat out and were
  never affected).
- The pin itself costs nothing to the measured threads on a 6-core phone
  but is a real change of conditions: numbers with `clockPinned: true` are
  "at sustained clock", which is also the state a phone is in during any
  real interaction burst.
- One `BENCH_STALLED` still fires once per phone run, in the first variant
  of the first round, while the app's window is coming up; medians of
  three rounds absorb it. A per-round stall flag is the next refinement.

## 9. The telemetry knob, priced (2026-09-28) — juice 1.10.0

§4 and §6 said telemetry context construction is ~40% of a dispatch even
when the logger drops it. `JuiceLoggerConfig.minLevel` (juice 1.10.0) is
the one knob: below it the framework does not build the per-event span
pair or emission entry at all. Default `Level.all` — nothing changes unless
set; errors, ignored events and failure emissions are never gated. This is
the same send measured with the knob at `Level.warning`, 5 rounds, median
[range]:

| send · fresh instance | default | minLevel = warning | saved |
|---|---:|---:|---:|
| Mac (Apple Silicon) | 2.79 µs [2.73–2.88] | 1.90 µs [1.81–1.94] | 32% |
| iPhone 17 Pro Max | 1.73 µs [1.64–1.78] | 1.12 µs [1.08–1.16] | 35% |

Ranges do not overlap on either machine. On the phone a Juice send drops
from 2.3× bloc's (§6, 0.76 µs) to ~1.5×; what remains is the async executor
(~0.4 µs) and the fresh use-case instance (~0.1 µs) — the design. The
knob buys about a third of a dispatch, for apps that dispatch enough events
per frame to notice; at ~1 µs per event that is thousands per frame.
`DevtoolsJuiceLogger` consumes the chatter, so the default stays where the
panel should work.

## 10. The wide scenario — built to hurt groups (2026-09-28)

Definition approved before any number existed (`lib/scenarios/wide.dart`):
N cells plus a **header** showing the sum over every cell; one update sets a
run of **K = N/20 consecutive cells** (5 of 100, 50 of 1000), so K cells
and the header change on every update. Groups put the targeting cost on
the emitter, which must name K+1 groups including a header the use case
has to remember; selectors put it on consumers, which run everywhere. The
question, unknown when the scenario was written: is naming 51 groups and
running 1001 set-intersections cheaper or dearer per frame than running
1001 selectors?

### Rebuild counts (deterministic, N = 100, K = 5)

| variant | cell builds | header builds | selector calls / update |
|---|---:|---:|---:|
| wide · juice · groups | 5 | 1 | 0 |
| wide · juice · JuiceSelector + groups | 5 | 1 | 6 |
| wide · juice · no groups | 100 | 1 | 0 |
| wide · bloc · BlocSelector | 5 | 1 | 101 |
| wide · bloc · BlocBuilder | 100 | 1 | 0 |
| wide · riverpod · family | 5 | 1 | 1 (one O(N) sum recompute) |
| wide · riverpod · select | 5 | 1 | 107 |
| wide · riverpod · watch | 100 | 1 | 0 |

Every tuned form builds exactly K+1, every naive form N+1 — the pinned
expectation. The selector column is the scenario's shape: groups 0, the
grouped selector K+1 (the group filter runs first), BlocSelector N+1,
Riverpod select N+1 plus its own bookkeeping. Riverpod's family form
(added 2026-09-29) sets the K cells one provider at a time and Riverpod
coalesces the K notifications into ONE recompute of the derived sum — an
O(N) walk over every cell provider, counted as 1 in the column.

### Frame cost — iPhone 17 Pro Max, clock pinned, N = 1000, K = 50

p50 build µs (probe subtracted), median of 3 rounds:

| variant | p50 | range | raster p50 | builds/update |
|---|---:|---:|---:|---:|
| wide · juice · JuiceSelector + groups | 655 | 653–657 | 494 | 50 |
| wide · juice · groups | 670 | 668–672 | 489 | 50 |
| wide · bloc · BlocSelector | 692 | 690–696 | 468 | 50 |
| wide · riverpod · select | 788 | 781–790 | 471 | 50 |
| wide · riverpod · watch | 1347 | 1345–1356 | 480 | 1000 |
| wide · juice · no groups | 1370 | 1338–1394 | 481 | 1000 |
| wide · bloc · BlocBuilder | 1502 | 1490–1526 | 488 | 1000 |

Verdicts among the tuned forms (computed from the recorded rounds; this
run predates the fix that lets the harness classify a K-build variant as
tuned):

- wide · juice · JuiceSelector + groups < wide · juice · groups: **faster** (2%)
- wide · juice · groups < wide · bloc · BlocSelector: **faster** (3%)
- wide · bloc · BlocSelector < wide · riverpod · select: **faster** (12%)

### Reading

- **The scenario did not turn against groups.** Naming 51 groups and
  filtering 1001 subscriptions costs the emitter side about the same as
  BlocSelector's 1001 selector calls (3%) and less than Riverpod's (15%).
  The emitter-side cost of groups is small even when the emitter must
  name many consumers.
- **The grouped selector edges plain groups (2%)**: with the group filter
  first, only the K+1 touched widgets run their selector, and a selector
  rebuild with a pre-extracted value is marginally cheaper than a
  `StatelessJuiceWidget` rebuild reading the bloc. Ranges are 2–6 µs, so
  "faster (2%)" is real and small — the harness's rule, applied honestly.
- **Cells → wide, tuned**: ×1.63–1.77 for groups and BlocSelector, ×2.08 for
  Riverpod select — Riverpod pays most for going wide, consistent with its
  per-consumer selector plus notifier bookkeeping. Naive forms grow only
  ×1.25: they were already rebuilding everything.
- **Naive is ~2× tuned** here as in every other table, once the clock is
  pinned.

---

## 11. Riverpod's family form — the missing variant (2026-09-29)

§1's "0 selector calls" column had one entry: groups. That was the
harness's choice of shape, not a property of Riverpod: one provider per
cell (`NotifierProvider.family`) is the other idiomatic Riverpod, and it
puts the targeting in the provider graph — source-side, like groups. It
was missing from both scenarios. This section adds it (`riverpod ·
family`, `wide · riverpod · family`; cells: one `Notifier<int>` per cell;
wide: the same plus a derived sum `Provider<int>` watching all N cells,
the K cells set one provider at a time as a family forces).

Same Mac as §7, Flutter 3.44.4 (`toolchainDrift: true` — not publishable
numbers), unpinned clock, 3 rounds for frames, 5 for dispatch. Raw data:
`results/timing_macos.json` (this run replaces §7's file; §7's numbers
stand as printed there).

### Rebuild counts (deterministic; also in §1 and §10)

Cells: family **1 build, 0 selector calls** — identical to groups. Wide:
family **K+1 builds, 1 recompute** of the derived sum per update (Riverpod
coalesces the K writes into one O(N) recompute); groups K+1 builds, 0.

### Frame cost, cells — p50 build µs, median of 3 rounds, N = 1000

| variant | p50 | range | builds/update |
|---|---:|---:|---:|
| **riverpod · family** | **663** | 630–689 | 1 |
| juice · JuiceSelector + groups | 707 | 672–728 | 1 |
| riverpod · select | 712 | 679–728 | 1 |
| juice · groups | 724 | 723–768 | 1 |
| juice · JuiceSelector | 736 | 706–748 | 1 |
| bloc · BlocSelector | 851 | 839–895 | 1 |
| riverpod · watch | 1893 | 1826–1913 | 1000 |
| juice · no groups | 1960 | 1946–2023 | 1000 |
| bloc · BlocBuilder | 2375 | 2360–2381 | 1000 |

Harness verdicts (adjacent pairs): family < JuiceSelector+groups **tie**
(6%); JuiceSelector+groups < select **tie** (1%); select < groups **tie**
(2%); groups < JuiceSelector **tie** (2%); JuiceSelector < BlocSelector
**faster** (14%). Read directly, family vs groups is 630–689 against
723–768: the ranges do not overlap, **family is faster by 8%** under the
harness's own rule. The chain of adjacent ties hides that; it is stated
here so it is not hidden.

### Frame cost, wide — p50 build µs, N = 1000, K = 50

| variant | p50 | range | builds/update |
|---|---:|---:|---:|
| **wide · riverpod · family** | **968** | 921–996 | 50 |
| wide · juice · groups | 1154 | 1130–1253 | 50 |
| wide · juice · JuiceSelector + groups | 1242 | 1156–1293 | 50 |
| wide · bloc · BlocSelector | 1432 | 1359–1463 | 50 |
| wide · riverpod · select | 1441 | 1424–1452 | 50 |
| wide · riverpod · watch | 2184 | 2133–2212 | 1000 |
| wide · juice · no groups | 2207 | 2153–2382 | 1000 |
| wide · bloc · BlocBuilder | 2702 | 2667–2746 | 1000 |

Harness verdicts: family < groups **faster (16%)**, ranges do not
overlap; groups < JuiceSelector+groups tie (7%); JuiceSelector+groups <
BlocSelector faster (13%); BlocSelector < select tie (1%). With the clock
probe subtracted (`tunedP50Normalized`) family < groups becomes a **tie
(5%)** — on this unpinned Mac the probe moved between variants, so the
raw and normalized verdicts disagree. A pinned phone run settles it; the
phone is where §10's wide numbers were taken, and this variant has not
run there yet.

### The phone — iPhone 17 Pro Max, clock pinned (same day)

Same phone and settings as §8/§10 (Flutter 3.44.4, drift; `clockPinned:
true`; the usual one `BENCH_STALLED` in the first variant of the first
round). Raw data: `results/timing_ios.json` (replaces §10's file; §10's
numbers stand as printed). p50 build µs, median of 3 rounds:

| cells, N = 1000 | p50 | range | probe µs |
|---|---:|---:|---:|
| juice · JuiceSelector + groups | 373 | 369–382 | 384 |
| **riverpod · family** | **373** | 370–373 | 384 |
| juice · JuiceSelector | 375 | 375–379 | 384 |
| riverpod · select | 379 | 379–380 | 389 |
| juice · groups | 382 | 374–386 | 384 |
| bloc · BlocSelector | 429 | 423–429 | 389 |
| riverpod · watch | 1050 | 1050–1059 | 389 |
| juice · no groups | 1077 | 1072–1105 | 387 |
| bloc · BlocBuilder | 1231 | 1207–1232 | 389 |

Verdicts: every adjacent tuned pair a **tie** down to BlocSelector
(family < JuiceSelector "faster" by 0.5% on non-overlapping ranges of
370–373 vs 375–379 — the rule's letter, not a finding). Family vs groups
directly: 373 vs 382, **2%**, ranges 1 µs apart. The Mac's 8% is 2% on
the pinned phone.

| wide, N = 1000, K = 50 | p50 | range | probe µs | raster p50 |
|---|---:|---:|---:|---:|
| juice · JuiceSelector + groups | 648 | 641–655 | 407 | 497 |
| **juice · groups** | **666** | 664–672 | 404 | 489 |
| bloc · BlocSelector | 688 | 677–690 | 384 | 461 |
| riverpod · family | 723 | 717–747 | **434** | **516** |
| riverpod · select | 792 | 777–793 | 393 | 466 |
| riverpod · watch | 1330 | 1323–1337 | 400 | 473 |
| juice · no groups | 1339 | 1325–1341 | 394 | 477 |
| bloc · BlocBuilder | 1498 | 1468–1534 | 401 | 479 |

Verdicts, raw: JuiceSelector+groups < groups faster (3%); groups <
BlocSelector faster (3%); BlocSelector < family faster (5%); family <
select faster (9%). **Groups beat family by 9% raw.** Normalized (probe
subtracted): groups vs family **tie (1%)** — the family variant's probe
ran at 434 µs against 384–407 for every other variant, and its raster
was the slowest too, so the chip was measurably slower during that
variant even with the pin on. The pin holds the clock; it does not hold
whatever else (thermal, memory pressure from 1,001 provider elements)
moved it here.

### Reading, both machines

- **The "0 selector calls" claim is not Juice's alone.** Any source-side
  targeting gives it; Riverpod's family form gives it with the same
  counts. §1's sentence about "where the targeting lives" stands, but the
  honest contrast is groups vs family, not groups vs selectors.
- **Family and groups are within noise of each other once the clock is
  accounted for.** Cells: family 8% under groups on the Mac, 2% on the
  pinned phone. Wide: family 16% under groups on the Mac raw, groups 9%
  under family on the phone raw — the two machines point in OPPOSITE
  directions, and each collapses to a tie when its probe is subtracted.
  The honest statement is a tie band of a few percent either way, not a
  winner. Groups still beat every consumer-side selector form on both
  machines, in both scenarios.
- **Why, mechanically.** Groups filter every subscribed widget on every
  emission (1001 `denyRebuild` set intersections through 1001 stream
  subscriptions); a family notifies only the touched providers' single
  consumers, and the derived sum does one O(N) read in one place. The
  emitter side is cheaper too: no group set to build. Groups' cost is the
  per-widget filter; family's is per-provider bookkeeping and a provider
  object per cell.
- **What §10's conclusion becomes.** "The scenario did not turn against
  groups" was measured against selector forms only. Against the family
  form the Mac says it did (16% raw) and the phone says it did not (9%
  raw the other way); normalized, both say tie. The READMEs now say:
  groups tie the selector forms and Riverpod's family form alike.
- **What this does not say.** Nothing about dispatch (family has none —
  a synchronous notifier write), nothing on the pinned toolchain. And a family is one provider object per cell: a
  1000-cell grid is 1000 providers plus 1000 element subscriptions, a
  shape Riverpod handles well here and one that is not the same design
  as one bloc naming groups.

---

## 12. The burst anomaly, explained (2026-09-29)

Every dispatch table shows Juice's **burst** shape (fire all 20,000 sends,
await the last) costing MORE per event than its sequential shape, while
bloc and Riverpod get cheaper in burst — Mac §11 run: 2.97 µs sequential,
5.65 burst. The breakdown now runs its layers in the burst shape at two
sizes. Same Mac, Flutter 3.44.4 (drift), silent logger, 5 rounds, median
[range]. Raw data: `results/breakdown_macos.json`.

| layer | sequential | burst n=2,000 | burst n=20,000 |
|---|---:|---:|---:|
| 4 awaited async hops (synthetic) | 0.50 [0.49–0.54] | **0.29** [0.27–0.44] | **1.27** [1.16–1.57] |
| send · fresh instance | 2.72 [2.67–2.75] | **2.48** [2.41–3.36] | **4.82** [3.84–5.12] |
| send · reused instance | 2.45 [2.42–2.51] | 2.33 [2.17–2.77] | 4.42 [3.32–4.94] |
| send · fresh, minLevel = warning | 1.81 [1.79–1.85] | **1.57** [1.54–2.14] | **2.93** [2.70–3.83] |

### Reading

- **At 2,000 in flight, burst is cheaper than sequential for every Juice
  row** — the throughput gain bloc and Riverpod show. The anomaly is not
  Juice's per-event path.
- **At 20,000 in flight, every row roughly doubles, and so does the
  synthetic hop row** (0.29 → 1.27 µs — four nested awaits, no Juice code
  at all). Twenty thousand un-awaited sends are twenty thousand chains of
  four pending futures each: the Dart microtask queue and the young-gen
  GC pay for the depth, superlinearly. The send rows grow by more than
  the hop row (+2.3 µs vs +1.0) because each in-flight send also holds
  its use-case instance, context, closures and status objects until it
  completes.
- **So the burst number is a benchmark artefact of its own size.** A real
  app never has 20,000 sends in flight; a burst between two frames is
  tens to hundreds, where burst is cheaper than sequential. bloc does not
  show it because `add()` returns nothing — its queue holds one pending
  handler per event, not a four-deep await chain — and Riverpod has no
  queue.
- **What it says about the hop depth.** The depth cost scales with hops ×
  in-flight. Collapsing send → dispatcher → executor from four awaited
  hops to the one structural await (the executor's, which closes the
  span) would shrink both the sequential hop term (~0.5 µs here) and the
  burst growth. Candidate, not decision: the breakdown's hop and burst
  rows are its gate.
- **Harness note.** The dispatch benchmark's burst at n = 20,000 measures
  Dart's async depth cost more than Juice's per-event cost. Whether to
  keep that size (and say so) or report burst at a realistic in-flight
  depth is a harness decision, recorded here rather than changed.

---

## 13. The cost follows the consumer (2026-09-29) — juice 1.10.0

§9 priced a knob someone has to find. 1.10.0 removes the need to find it:
a logger may declare the lowest level it keeps (`LevelAwareJuiceLogger`)
and the framework builds nothing below that. `DefaultJuiceLogger` declares
what its filter already does — everything in debug, nothing in profile or
release — so an app that configures NOTHING gets the knob's saving in
release and loses no line it ever printed. Same Mac, Flutter 3.44.4
(drift), release build, 5 rounds, median [range]. Raw data:
`results/breakdown_macos.json`.

| send · fresh instance | µs |
|---|---:|
| silent logger that declares nothing (the old out-of-the-box cost) | 2.72 [2.65–2.80] |
| `minLevel = warning` set by hand (§9's knob) | 1.82 [1.80–1.85] |
| **`DefaultJuiceLogger`, nothing configured** | **1.82 [1.79–1.85]** |

The unconfigured row lands on the knob row: **33% of a send, by default**.
Against bloc's 1.02 µs on this machine (§11 run) a Juice send out of the
box is ~1.8× in release, down from ~2.7–3×.

**Reading the dispatch tables after 1.10.0.** `juice (default logger)` is
now the cheap row in release (it declares; chatter is not built) and
`juice (silent logger)` the dear one (the benchmark's silent logger
declares nothing, so everything is built and thrown away). §3, §6, §7 and
§11's dispatch rows predate this and stand as measured.

