# juice_llm

On-device LLM inference as a Juice bloc — model lifecycle, **streaming
generation**, and embeddings behind a swappable runtime seam. Private by
construction: inference runs in-process, the package has no telemetry, and
nothing you generate leaves the device through it.

```dart
final llm = LlmBloc.withConfig(LlmConfig()); // Echo runtime — no downloads
llm.loadModel(myModel);
llm.generate(LlmRequest(
  requestId: 'r1',
  messages: [LlmMessage.user('a quiet morning by the river')],
));
// A widget bound to LlmGroups.gen('r1') reads session.text as tokens stream.
```

## What it owns

- **Model lifecycle** — a state machine: `absent → fetching → fetched →
  loading → ready` (and `error`, loudly).
- **Generation sessions** — each request streams into a `GenerationSession`
  (`queued → streaming → done | cancelled | failed`) on its own rebuild group.
- **Embeddings** — one-shot vectors via `embed()`.

It does **not** own prompts, retrieval, or RAG composition (that's app truth —
see *Synthesis, not recall*), nor the runtime itself (that's the seam).

## Seams

```dart
// The runtime. Marry llama.cpp / Ollama / MediaPipe / a cloud endpoint here;
// the bloc never grows a vendor opinion. Default: EchoLlmProvider.
abstract class LlmProvider {
  Set<LlmCapability> get capabilities;     // {text, embeddings, vision}
  Future<void> load(String modelPath, LlmLoadOptions options);
  Future<void> unload();
  Stream<LlmChunk> generate(LlmRequest request); // cancel ⇒ stop the runtime
  Future<List<double>> embed(String text);
  Future<void> dispose();
}

// Weight acquisition (download + verify). Default: FileModelSource.
abstract class ModelSource {
  Stream<ModelFetchProgress> fetch(LlmModel model, String destinationPath);
  Future<bool> isPresent(LlmModel model, String destinationPath);
  Future<void> delete(LlmModel model, String destinationPath);
}
```

## Runtimes

The package ships **`EchoLlmProvider`** — a pure-Dart, zero-dependency runtime
that streams a reflective reply word-by-word. It runs on any platform with no
native code or downloads, so the example and your tests work out of the box,
and it's the reference implementation of the seam contract (streaming,
cancellation, capabilities).

The full provider matrix and package layout (core / `juice_llm_cloud` /
`juice_llm_llamacpp`) is in [`doc/PROVIDERS.md`](doc/PROVIDERS.md).

For a **real model today**, the example ships `OllamaLlmProvider` (OpenAI-style
streaming over HTTP):

```sh
brew install ollama && ollama serve
ollama pull gemma3:1b
```
```dart
LlmBloc.withConfig(LlmConfig(provider: OllamaLlmProvider(model: 'gemma3:1b')));
```

An **embedded** llama.cpp FFI runtime (GGUF weights, Metal, no server process —
for app-store packaging) is the documented next step; it's a straightforward
implementation of the same `LlmProvider` seam.

## Streaming, throttled

Tokens arrive as state emissions on `LlmGroups.gen(requestId)`, **coalesced to
at most one emission per `config.streamThrottle`** (default 50 ms) with a
guaranteed final emission on terminal status. A widget bound to one request's
group rebuilds at a sane rate no matter how fast the runtime decodes; no other
widget rebuilds. This is the package's core performance contract.

## Concurrency

One generation runs at a time — `GenerateEvent` is `sequential`, so requests
queue in order against the single runtime context. `CancelGenerationEvent` is
`concurrent`, so it runs *during* a generation and stops the runtime
out-of-band by cancelling the provider stream. However a stream ends — natural
completion, error, or cancel — it funnels through one terminal emission, so a
session always reaches a terminal status and the queue is never wedged.

## Fail-loud

- Generate with no ready model → an immediately-`failed` session (never a
  silent wait for a model that was never requested).
- A load failure (OOM / format mismatch) → `modelStatus: error` with the
  reason; **no fallback model is ever silently substituted**.
- A `ModelSource` checksum mismatch deletes the corrupt file and throws —
  unverified weights are never loaded.
- `embed()` without the capability throws `UnsupportedError`.
- Loading/unloading while a generation is active is refused (cancel first).

## Synthesis, not recall

Small on-device models (1–4B) are strong at **synthesis, narration, and
summarization of text you put in the prompt** and unreliable at **factual
recall about specific places, people, or events** — they confabulate fluently.
Treat the model as a writer, not an encyclopedia: facts should come from
retrieval (app-side RAG over citable sources) or the user's own content. This
package keeps retrieval out of its domain precisely so that boundary stays
visible in your app code.

## Status

`0.1.0` — Reviewed. Bloc, seams, lifecycle, throttled streaming, and the Echo
runtime are complete and fully tested headlessly. The real-model path is proven
via the example's Ollama provider; an embedded FFI runtime is the maturation
step toward the dogfood milestone. See `doc/SPEC.md`.
