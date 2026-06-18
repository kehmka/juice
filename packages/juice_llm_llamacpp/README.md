# juice_llm_llamacpp

Embedded on-device LLM runtime for [`juice_llm`](https://pub.dev/packages/juice_llm) —
an `LlamaCppProvider` that runs **GGUF models on llama.cpp (Metal/CPU)**,
in-process and private, via [`llama_cpp_dart`](https://pub.dev/packages/llama_cpp_dart).

```dart
final llm = LlmBloc.withConfig(LlmConfig(
  provider: LlamaCppProvider(libraryPath: '/path/to/libllama.dylib'), // macOS dev
  resolvePath: (model) => '/path/to/model.gguf',
));
llm.loadModel(myModel);
llm.generate(LlmRequest(requestId: 'r1', messages: [LlmMessage.user('hi')]));
```

Nothing else in the app changes — it's just an `LlmProvider`. Swap it for the
`EchoLlmProvider` default (or an HTTP provider) without touching widgets or use
cases.

## Native binary (the one setup step)

This package is pure Dart. The native llama.cpp library is `llama_cpp_dart`'s
concern — grab the prebuilt binary from its
[GitHub Releases](https://github.com/netdur/llama_cpp_dart/releases):

| Target | Artifact | Wire it up |
|---|---|---|
| **macOS dev / CLI / tests** | `macos-libllama.zip` (`libllama.dylib` + siblings) | unzip anywhere, `LlamaCppProvider(libraryPath: '…/libllama.dylib')`. Downloaded dylibs are Gatekeeper-quarantined — `xattr -dr com.apple.quarantine <dir>`. |
| **iOS / macOS app** | `llama.xcframework` | drag into Xcode → **Embed & Sign**, then `LlamaCppProvider(useProcessSymbols: true)` (no path; dyld resolves it). |

## Cancellation

Cancelling the generation stream cancels the underlying generation. On the
published `llama_cpp_dart` 0.9.0-dev.9 this is **soft** — token *delivery* stops
immediately (the session reaches `cancelled`), but the worker finishes the
current decode. That's fine for short generations (e.g. a one-line reflection).

True mid-decode interrupt lands when
[netdur/llama_cpp_dart#106](https://github.com/netdur/llama_cpp_dart/pull/106)
merges (an event-loop-starvation fix); no change is needed here when it does.

## Models

Any GGUF llama.cpp loads. Gemma 4 (Apache-2.0, mirror-able) is a good on-device
pick: `gemma-4-E2B-it-qat` ~2.6 GB Q4 text-only. Memory (not policy) is the
device ceiling — ~2.6 GB fits 8 GB-RAM iPhones comfortably, marginal on 6 GB;
context length is the tuning knob. Weights are downloaded at runtime (a
`ModelSource`), not bundled — see `juice_llm`'s provisioning notes.

## Embeddings

`embed()` maps to `llama_cpp_dart`'s embedding pass (for `juice_llm`'s semantic
search). It requires the engine to be configured for embeddings on the loaded
model.

## Status

`0.1.0` — built and verified end-to-end on macOS/Metal (real model through
`LlmBloc`: streaming generation, KV reuse across requests, cancel). The
embedded runtime behind `juice_llm`'s `LlmProvider` seam.
