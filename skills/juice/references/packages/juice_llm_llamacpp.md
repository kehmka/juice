---
card_schema: "1.0"
package: juice_llm_llamacpp
version: 0.1.0
requires:
  juice_llm: ">=0.1.0"
  llama_cpp_dart: ">=0.9.0-dev.9 <0.10.0"
updated: 2026-06-17
---

# juice_llm_llamacpp — AI card

> The embedded on-device runtime for `juice_llm`: `LlamaCppProvider` runs GGUF
> models on llama.cpp (Metal/CPU) in-process via `llama_cpp_dart`. A pure-Dart
> adapter — the native binary is `llama_cpp_dart`'s concern.

## Purpose

**Owns:** mapping `juice_llm`'s `LlmProvider` seam onto `llama_cpp_dart`'s
`LlamaEngine`.
**Does NOT own:** the bloc/streaming/lifecycle (that's `juice_llm`), prompts /
RAG (app-side), or the native library (that's `llama_cpp_dart`, prebuilt).

## Construct

```dart
// macOS dev / CLI / tests — point at a downloaded libllama.dylib:
LlamaCppProvider(libraryPath: '/path/to/libllama.dylib')
// iOS / macOS app — embed llama.xcframework (Embed & Sign), no path:
LlamaCppProvider(useProcessSymbols: true)

LlmBloc.withConfig(LlmConfig(
  provider: LlamaCppProvider(libraryPath: lib),
  resolvePath: (model) => '/path/to/model.gguf',
));
```

## Mapping (seam → llama_cpp_dart)

| `LlmProvider` | `llama_cpp_dart` |
|---|---|
| `load(modelPath, opts)` | `LlamaEngine.spawn`/`spawnFromProcess` (gpuLayers, nCtx) + `createChat` |
| `generate(request)` | `chat.clearHistory()` → add messages by role → `chat.generate(sampler, maxTokens)`; `TokenEvent`→`LlmChunk`, `DoneEvent`→done |
| cancel (stream cancel) | cancels `chat.generate` (soft on dev.9 — see below) |
| `embed(text)` | `engine.embed(text).vector` |
| `unload`/`dispose` | `engine.dispose()` |

One reusable chat, `clearHistory` per request ⇒ stateless one-shot. The worker
also clears the KV cache on each chat generate, so repeated requests don't
collide. Generation is one-at-a-time (engine single-active), matching
`LlmBloc`'s `sequential` queue.

## Native binary

Prebuilt from `llama_cpp_dart`'s GitHub Releases. macOS: `macos-libllama.zip`
(`xattr -dr com.apple.quarantine` after download). iOS/macOS app:
`llama.xcframework`, Embed & Sign. This package ships no native assets.

## Cancellation (important)

On published `llama_cpp_dart` 0.9.0-dev.9, cancel is **soft**: delivery stops
and the session reaches `cancelled`, but the worker finishes the current decode
(fine for short generations). True mid-decode interrupt arrives with
netdur/llama_cpp_dart#106; no change needed here.

## Anti-patterns

- ❌ Building the native lib by hand — use the prebuilt release binary.
- ❌ Bundling weights in the app — download at runtime via a `ModelSource`.
- ❌ Asking a small model for facts — synthesis only; retrieval is app-side.

## See also

`README.md` · `juice_llm` (the bloc/seam) · `ROADMAP.md` decision #7 (runtime
providers live outside core).
