# Results — 2026-09-28

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
