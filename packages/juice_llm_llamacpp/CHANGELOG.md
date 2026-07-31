# Changelog

## 0.2.2

### Changed

- Allow `juice_llm` 0.3.0 (safe-point preempt, non-hanging stop, engine
  lease/trace). The provider seam this package implements is unchanged;
  the old `^0.2.0` pin was blocking hosts from the 0.3.0 concurrency
  fixes.

## 0.2.1

### Fixed

- **`gemmaChatFormat` no longer drops the system prompt after a leading
  assistant turn.** Gemma has no `system` role, so system text is folded into a
  user turn — but it was only folded when the *first* turn was a user turn. Any
  conversation that opened with an assistant/model turn (e.g. an assistant that
  greets first) silently lost its entire system message — instructions and
  grounding included. The system text now folds into the first *user* turn
  regardless of preceding assistant turns, and if there is no user turn it is
  emitted as a leading user turn rather than dropped. Single-shot
  `[system, user]` prompts are unaffected. Regression tests added.

## 0.2.0

### Added — multimodal (image + audio) input

- **Vision & audio through one model.** Pass `LlmLoadOptions.projectorPath` (an
  `mmproj` GGUF) to `load` and the engine loads the vision/audio encoder via
  llama.cpp's `mtmd`. Requests then carry `LlmMessage.images` / `.audio`; the
  provider splices them at `<__media__>` markers. Verified end-to-end on
  macOS/Metal: Gemma 4 E2B described a real photo accurately (color, spatial
  position, mood) at ~73 tok/s, encode ~120 ms. Gemma 4 E2B's projector carries
  **both** encoders (`has_vision_encoder` + `has_audio_encoder`).
- **`gemmaChatFormat` is now media-aware** — injects one `<__media__>` marker
  per image/audio item into its turn, in lock-step with the order the provider
  hands bytes to llama.cpp, so embeddings land at the right marker.
- **Honest capabilities** — `capabilities` gains `vision` + `audio` only once a
  projector has actually loaded (`engine.multimodalLoaded`), never as an
  unbacked promise. A request with media but no projector loaded fails loud.
- Requires `juice_llm` ^0.2.0 (for `LlmLoadOptions.projectorPath`,
  `LlmMessage.audio`, `LlmCapability.audio`).

### Known caveat

- On Metal, llama.cpp raises a teardown assertion
  (`ggml-metal-device.m: GGML_ASSERT([rsets->data count] == 0)`) during process
  finalization *after* a multimodal run — generation output is unaffected.
  Tracked upstream (ggml-org/llama.cpp#17869); keep the engine loaded for the
  app's lifetime so dispose-at-exit is rare.

## 0.1.1

### Added

- **`chatFormat` option + `gemmaChatFormat`** — for models whose embedded chat
  template llama.cpp can't apply (Gemma 4 ships tool-use Jinja the runtime can't
  parse). When set, the prompt is built manually and generation uses the raw
  session path instead of `chat.generate`. `gemmaChatFormat` handles the
  `<start_of_turn>user … <end_of_turn><start_of_turn>model` format (no system
  role — system folds into the first user turn). Verified end-to-end with
  Gemma 4 E2B; the default (embedded-template) path is unchanged for SmolLM2 /
  Qwen / etc.

## 0.1.0

Initial release.

- `LlamaCppProvider` — an `LlmProvider` (juice_llm) backed by llama.cpp
  (GGUF, Metal/CPU) through `llama_cpp_dart`'s off-isolate `LlamaEngine`.
- `load` / `generate` (streaming, chat-templated) / `embed` / `unload` /
  `dispose`, mapping the seam onto `LlamaEngine`. One reusable chat with
  per-request `clearHistory` ⇒ stateless one-shot generation (no KV-cache
  conflict across requests).
- Native binary provisioning documented (macOS dylib via `libraryPath`; iOS /
  macOS app via embedded `llama.xcframework` + `useProcessSymbols`).
- Soft cancellation on `llama_cpp_dart` 0.9.0-dev.9 (delivery stops; session
  reaches `cancelled`); true mid-decode interrupt arrives with
  netdur/llama_cpp_dart#106.
- Verified end-to-end on macOS/Metal with a real GGUF through `LlmBloc`
  (integration test, local-only — skipped without the native lib + a model).
