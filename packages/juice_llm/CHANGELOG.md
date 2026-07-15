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
