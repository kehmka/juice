# Changelog

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
