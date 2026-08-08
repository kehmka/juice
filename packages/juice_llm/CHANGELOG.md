## 0.4.1

- THE LATE-TEARDOWN UN-WEDGE: a wedge is a claim — "this native call
  never returns." When the stuck teardown eventually DOES return, the
  claim is falsified and the flag now lifts, restoring the engine without
  an app restart (field log 2026-08-08: a mid-prefill stop's teardown
  came back 89 seconds after the wedge was declared; the runtime had
  recovered, but the sticky flag kept a healthy engine condemned). Only
  the wedging teardown's own completion lifts it — a different teardown
  finishing proves nothing about the stuck one. Traced loudly as
  `un-wedged <id>`.

## 0.4.0

- THE TEARDOWN CEILING + `LlmBloc.engineWedged`: a stopped generation's
  provider teardown that never returns (a cancel landing mid-native-call
  has no yield boundary to complete at) used to poison the generation
  queue — every queued generation and lease behind it waited FOREVER
  (Amoli, 2026-08-01: one wedged tag item's teardown starved the colloquy,
  the background drain, and a card composer for twenty minutes, with the
  engine idle the whole time). Past `LlmConfig.teardownPatience` (default
  8s — a healthy cancel takes milliseconds) the bloc declares the engine
  WEDGED: the queue tail resolves, every queued and future
  `beginGeneration` completes fast with `error: 'engine wedged — restart
  required'`, `acquireEngine` throws immediately, and
  `preemptAtSafePoint` reports the engine free so callers reach their own
  fast failure. No in-process recovery is attempted — a native thread
  stuck mid-call cannot be salvaged from Dart, and pretending otherwise
  would be a silent fallback; the bloc says "restart" loudly instead.
- `onEngineTrace` vocabulary grows: `wedged …`, `refused … (engine
  wedged)`, `lease-refused (engine wedged)`, and a `(late — after wedge
  declaration)` suffix on a teardown that eventually returns after all.

## 0.3.0

- `LlmBloc.preemptAtSafePoint({where, patience})`: preempt the active
  generation at the next SAFE point. Cancelling a provider mid-PREFILL can
  wedge a native runtime (LiteRT, Amoli 2026-07-26); once tokens stream,
  every chunk is a yield boundary and cancellation is prompt. Already
  decoding → cancel now; still prefilling → wait for the first chunk, then
  cancel; no chunk within `patience` → leave it running and return false.
- `stopGeneration` no longer blocks its caller on the provider's teardown:
  an `async*` cancel only completes at a yield boundary, and a runtime
  wedged mid-native-call has none — the old `await sub.cancel()` hung a
  caller forever, outside every watchdog. The GENERATION QUEUE still waits
  for the real teardown (one live session per model), chained onto the
  queue tail instead of the caller.

## 0.2.2

- `LlmBloc.acquireEngine()` / `EngineLease`: exclusive engine ownership
  for callers that hold a session across turns (tool-loop conversations).
  Native runtimes keep ONE live session per model, so a generation starting
  between a conversation's turns destroyed the conversation's session
  ("Bad state: Session is closed"). While a lease is held, `beginGeneration`
  queues behind release; serialization is turn-grained, the lease is
  lifetime-grained. `engineLeased` exposes the state.

# Changelog

## 0.2.1

### Fixed

- **`beginGeneration` is now serialized at the resource** — one runtime
  context means one stream at a time, regardless of caller. Service-layer
  callers that await the method directly (bypassing the `GenerateEvent`
  queue) used to race straight into the provider; harmless while nothing
  generated in the background, but constant collisions once a device
  enriches its well continuously (LiteRT on iPhone, 2026-07-14 — the
  colloquy's "I lost my place" every ask). A call made mid-generation now
  waits its turn.

### Documented

- **The caller-side preemption pattern** (README → Concurrency; SPEC):
  priority stays out of the API — an interactive caller names its lanes via
  `requestId`, checks `activeRequestId`, and `stopGeneration()`s a background
  stream rather than waiting it out. Covered by two new tests (FIFO turns for
  direct awaiters; preempt-then-generate).

## 0.2.0

### Added (multimodal input — non-breaking)

- **`LlmCapability.audio`** — alongside the existing `vision`, for models that
  take audio clips (voice memos) as input.
- **`LlmMessage.audio`** — `List<Uint8List>` of encoded audio (WAV/MP3/FLAC),
  mirroring the existing `images`. A multimodal provider feeds them to the model;
  text-only models ignore them.
- **`LlmLoadOptions.projectorPath`** — optional path to a multimodal projector
  (mmproj GGUF). When set, a multimodal-capable provider loads it and enables
  image/audio input. The projector pairs with the weights; the app acquires it
  and passes the resolved path (app-orchestrated provisioning — the acquisition
  seam stays single-artifact for now).

All additive — existing text-only usage is unchanged.

## 0.1.1

### Fixed

- **`FetchModelEvent` crashed** with `type 'int' is not a subtype of 'double?'`.
  `FetchModelUseCase` emitted `fetchProgress: 0` (int) and `LlmState.copyWith`
  cast it `as double?`. Now emits `0.0` and `copyWith` coerces via `num?
  .toDouble()`. The whole fetch lifecycle was untested (Echo/Fake providers skip
  it); a fetch-lifecycle regression test now covers it. Surfaced by the Glean
  dogfood (first real `ModelSource`).

## 0.1.0

Initial release — Reviewed.

- `LlmBloc`: on-device LLM inference as a bloc — model-lifecycle state machine
  (absent → fetching → fetched → loading → ready / error) plus streaming
  generation and embedding sessions.
- Seams: `LlmProvider` (runtime) and `ModelSource` (weight acquisition +
  checksum verify), following the `AuthProvider` / `FlagsSource` pattern.
- `EchoLlmProvider`: pure-Dart, zero-dependency reference runtime — the
  runnable default (streams a reflective reply word-by-word; deterministic
  embeddings).
- Per-request rebuild groups (`LlmGroups.gen(id)`) with **throttled streaming
  emissions** (coalesced to ≤ one per `streamThrottle`, terminal always
  flushed).
- Concurrency: `GenerateEvent` `sequential` (one runtime context),
  `CancelGenerationEvent` `concurrent` (out-of-band stop); one terminal
  finalize point so the queue never wedges on cancel.
- Fail-loud: no-model generate fails its session; load failure surfaces with no
  silent fallback model; checksum mismatch deletes + throws; embeddings
  capability guard; no load/unload under an active generation.
- Bounded session retention (`maxRetainedSessions`) + explicit `evictSession`.
- Example app: Echo runtime by default, with `OllamaLlmProvider` (real local
  model over HTTP) as the seam-swap reference.
