# Changelog

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
