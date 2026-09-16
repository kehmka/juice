---
card_schema: "1.0"
package: juice_llm_llamacpp
version: 0.2.3
requires:
  juice_llm: ">=0.3.0 <1.0.0"
  llama_cpp_dart: ">=0.9.0-dev.9 <0.10.0"
updated: 2026-09-15
---

# juice_llm_llamacpp — AI card

> The embedded on-device runtime for `juice_llm`: `LlamaCppProvider` runs GGUF
> models on llama.cpp (Metal/CPU) in-process via `llama_cpp_dart`, text and —
> with an `mmproj` projector — image/audio input. A pure-Dart adapter; the
> native binary is `llama_cpp_dart`'s concern.

## Purpose

**Owns:** mapping `juice_llm`'s `LlmProvider` seam onto `llama_cpp_dart`'s
`LlamaEngine`, plus manual prompt rendering (`ChatFormat`) for models whose
embedded chat template llama.cpp can't apply.
**Does NOT own:** the bloc/streaming/lifecycle (that's `juice_llm`), prompts /
RAG (app-side), or the native library (that's `llama_cpp_dart`, prebuilt).

## Install

`juice_llm` `>=0.3.0 <1.0.0` (this package implements only the stable provider
seam, hence the wide range) + `llama_cpp_dart` `>=0.9.0-dev.9 <0.10.0`. No
direct `juice` dependency. Native binary: prebuilt from `llama_cpp_dart`'s
GitHub Releases — macOS `macos-libllama.zip` (`xattr -dr com.apple.quarantine`
after download); iOS / macOS app `llama.xcframework`, Embed & Sign. This
package ships no native assets.

## Construct

```dart
// macOS dev / CLI / tests — point at a downloaded libllama.dylib:
LlamaCppProvider(libraryPath: '/path/to/libllama.dylib')
// iOS / macOS app — embed llama.xcframework (Embed & Sign), no path:
LlamaCppProvider(useProcessSymbols: true)
// Gemma 4 (embedded template unparseable by llama.cpp) — render manually:
LlamaCppProvider(libraryPath: lib, chatFormat: gemmaChatFormat)

LlmBloc.withConfig(LlmConfig(
  provider: LlamaCppProvider(libraryPath: lib),
  resolvePath: (model) => '/path/to/model.gguf',
));
```

Constructor asserts `libraryPath != null || useProcessSymbols`. `capabilities`
(declared) defaults to `{text, embeddings}`; `vision` + `audio` are never
declared — they are added at runtime only once a projector loads.

## Seams (`LlmProvider` → `llama_cpp_dart`)

| `LlmProvider` | `llama_cpp_dart` |
|---|---|
| `load(modelPath, opts)` | `LlamaEngine.spawn(libraryPath)` / `spawnFromProcess` with `ModelParams(gpuLayers)`, `ContextParams(nCtx: contextTokens, nSeqMax: 1)`, and `MultimodalParams(mmprojPath: projectorPath, useGpu: gpuLayers > 0)` when `opts.projectorPath != null`; then `createSession` (chatFormat set) or `createChat` |
| `generate(request)` | **template path:** `chat.clearHistory()` → `addSystem`/`addUser(content, media:)`/`addAssistant` → `chat.generate(sampler, maxTokens)`. **chatFormat path:** `session.clear()` → `session.generate(prompt: chatFormat(messages), addSpecial: true, media, sampler, maxTokens)`. `TokenEvent`→`LlmChunk(text, tokens: 1)` (empty text skipped), `DoneEvent`→`LlmChunk(trailingText, done: true)` |
| cancel (stream cancel) | cancels the `await for` → cancels generation (soft on dev.9 — see Invariants) |
| `embed(text)` | `engine.embed(text).vector.toList()` |
| `unload` / `dispose` | `engine.dispose()` (`dispose` ≡ `unload`) |

`SamplerParams(temperature, topP)` from `request.params`; `maxTokens =
params.maxTokens ?? 512`. Each `generate` is a stateless one-shot (history /
session KV reset per call); generation is one-at-a-time (engine single-active),
matching `LlmBloc`'s `sequential` queue.

## API

| Symbol | Signature / meaning |
|---|---|
| `LlamaCppProvider({String? libraryPath, bool useProcessSymbols = false, ChatFormat? chatFormat, Set<LlmCapability> capabilities = const {text, embeddings}})` | the provider; `name` → `'llama_cpp'` |
| `Set<LlmCapability> get capabilities` | declared set ∪ `{vision, audio}` iff `engine.multimodalLoaded` — reflects what actually loaded |
| `typedef ChatFormat = String Function(List<LlmMessage> messages)` | manual prompt renderer; when set, the raw session path replaces the model's chat template |
| `String gemmaChatFormat(List<LlmMessage>)` | `<start_of_turn>user … <end_of_turn>` / `<start_of_turn>model` format (below) |
| `const String kMediaMarker = '<__media__>'` | the marker mtmd substitutes with one media item's embeddings |

**`gemmaChatFormat`:** system messages (joined with `\n`) are folded into the
first **user** turn as `'$system\n\n$content'` — regardless of assistant turns
before it, so a conversation that opens with an assistant/model greeting keeps
its system prompt. If there is no user turn at all the system text is emitted
as a leading user turn, never dropped. `assistant` → `model`, everything else
→ `user`. Each turn gets one `<__media__>` per `images` + `audio` item
(images first), newline-joined and prepended to the content. Output ends with
`<start_of_turn>model\n`.

## Multimodal (0.2.0+)

1. `load(path, LlmLoadOptions(projectorPath: '/path/to/mmproj.gguf'))` — the
   engine loads the vision/audio encoder via llama.cpp `mtmd`. A projector
   that was requested but didn't load throws `LlmProviderException` (never a
   silent text-only downgrade).
2. Put bytes on the message: `LlmMessage.images` / `LlmMessage.audio`
   (`List<Uint8List>`). The provider hands them to llama.cpp as
   `LlamaMedia.imageBytes` / `audioBytes`, images before audio per message.
3. `capabilities` now contains `vision` + `audio`; check it before offering
   media in the UI.

Marker/byte alignment: on the chatFormat path, media is collected across all
non-system turns in order and the format injects markers in the same order —
these must stay in lock-step. On the template path `addUser(..., media:)`
prepends the markers itself.

## Testing

`test/gemma_chat_format_test.dart` covers the fold rules (pure function — no
native lib). `test/llama_cpp_integration_test.dart` drives a real GGUF through
`LlmBloc`; it self-skips unless `LLAMA_LIB` + `LLAMA_MODEL` are set.

## Failure modes

| Condition | Result |
|---|---|
| `load` fails (spawn / chat / session) | engine disposed; `LlmProviderException('llama.cpp load failed', cause: e)` |
| `projectorPath` given but projector didn't load | `LlmProviderException('multimodal projector failed to load: …')` |
| `generate` / `embed` with no model loaded | `LlmProviderException` |
| request carries media, no projector loaded | `LlmProviderException` (fail loud, before any decode) |
| `embed` with `embeddings` not in declared capabilities | `UnsupportedError` |

## Anti-patterns

- ❌ Building the native lib by hand — use the prebuilt release binary.
- ❌ Bundling weights in the app — download at runtime via a `ModelSource`.
- ❌ Declaring `vision`/`audio` in the constructor `capabilities` — pass a
  projector; the provider adds them once it actually loads.
- ❌ Using `gemmaChatFormat` for SmolLM2 / Qwen — their embedded templates
  work; leave `chatFormat` null.
- ❌ Asking a small model for facts — synthesis only; retrieval is app-side.

## Invariants

- **Cancellation is soft** on published `llama_cpp_dart` 0.9.0-dev.9: delivery
  stops and the session reaches `cancelled`, but the worker finishes the
  current decode. True mid-decode interrupt arrives with
  netdur/llama_cpp_dart#106; no change needed here.
- **Media on the template path is only read from `user` turns**
  (`addUser(..., media:)`); the chatFormat path takes media from every
  non-system turn.
- **Metal teardown caveat:** after a multimodal run, llama.cpp raises
  `GGML_ASSERT([rsets->data count] == 0)` (`ggml-metal-device.m`) during
  process finalization — output is unaffected. Upstream
  ggml-org/llama.cpp#17869. Keep the engine loaded for the app's lifetime so
  dispose-at-exit is rare.
- Re-`load` on a loaded provider unloads first; `chatFormat` is fixed at
  construction (it selects session vs chat at `load`).

## See also

`README.md` · `CHANGELOG.md` · `juice_llm` (the bloc/seam, its own card) ·
`ROADMAP.md` decision #7 (runtime providers live outside core).
