# Changelog

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
