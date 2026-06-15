---
card_schema: "1.0"
package: juice_llm
version: 0.1.0
requires:
  juice: ">=1.5.0"
updated: 2026-06-11
---

# juice_llm — AI card

> On-device LLM inference as a bloc: model lifecycle + streaming generation +
> embeddings behind a swappable `LlmProvider` runtime seam and a `ModelSource`
> acquisition seam. Private by construction (in-process, no telemetry). Read
> repo `AGENTS.md` for the Juice mental model + gotchas.

## Purpose

**Owns:** model-acquisition + runtime lifecycle, and generation/embedding
session state.
**Does NOT own:** prompts / RAG composition / retrieval (app truth), or the
runtime (the `LlmProvider` seam). A runtime is a provider impl, not a glue
package.

## When to use

Running an open model (Gemma-class) privately on device with a real state
machine: download-with-progress, load/unload, streaming generation rendered as
state, embeddings. Reach for it when you want token streaming as selective
rebuilds and the runtime swappable (llama.cpp / Ollama / MediaPipe / cloud).

## Install

```yaml
dependencies:
  juice_llm: ^0.1.0
```

## Construct

Default `EchoLlmProvider` (pure-Dart, no downloads) so it runs anywhere:

```dart
final llm = LlmBloc.withConfig(LlmConfig());
llm.loadModel(model);                  // Echo: straight to ready
llm.generate(LlmRequest(requestId: 'r1', messages: [LlmMessage.user('hi')]));
final vec = await llm.embed('text');   // if model supports embeddings
```

## Seams

```dart
abstract class LlmProvider {            // runtime; default EchoLlmProvider
  Set<LlmCapability> get capabilities;  // {text, embeddings, vision}
  Future<void> load(String modelPath, LlmLoadOptions options);
  Future<void> unload();
  Stream<LlmChunk> generate(LlmRequest request); // listener-cancel ⇒ stop runtime
  Future<List<double>> embed(String text);       // throws if unsupported
  Future<void> dispose();
}
abstract class ModelSource {            // weights; default FileModelSource
  Stream<ModelFetchProgress> fetch(LlmModel model, String destinationPath); // verify sha256
  Future<bool> isPresent(LlmModel model, String destinationPath);
  Future<void> delete(LlmModel model, String destinationPath);
}
```

## API

```dart
void fetchModel(LlmModel model);  // download via ModelSource (droppable)
void loadModel(LlmModel model);   // → runtime (sequential; refused while generating)
void unloadModel();
void generate(LlmRequest request);// sequential; streams into a session
void cancel(String requestId);    // concurrent; stops the runtime out-of-band
void evictSession(String requestId);
Future<List<double>> embed(String text); // awaits the provider
bool get isGenerating; String? get activeRequestId;
```

## Events

| Event | Concurrency | Effect |
|---|---|---|
| `InitializeLlmEvent(config)` | — | apply config, probe `isPresent`, optional auto-load |
| `FetchModelEvent(model)` | droppable | download + verify; progress → `llm:fetch` |
| `LoadModelEvent(model)` | sequential | load runtime; **refused while generating** |
| `UnloadModelEvent` | sequential | free runtime; refused while generating |
| `GenerateEvent(request)` | sequential | stream a completion into a session |
| `CancelGenerationEvent(id)` | concurrent | cancel the in-flight stream (out-of-band) |
| `EmbedEvent(text)` | sequential | vector via the event's `result` future |
| `EvictSessionEvent(id)` | — | drop a retained terminal session |

## State

```dart
class LlmState {                       // BlocState
  LlmModelStatus modelStatus;          // absent|fetching|fetched|loading|ready|error
  String? activeModelId;
  double? fetchProgress;               // 0..1 while fetching
  Map<String, GenerationSession> sessions; // requestId → session
  String? error;                       // loud lifecycle error
}
class GenerationSession {
  String requestId; SessionStatus status; // queued|streaming|done|cancelled|failed
  String text; int tokens; String? error;
}
```

## Rebuild groups

| Group | Emitted when |
|---|---|
| `LlmGroups.gen(id)` → `llm:gen:<id>` | that request's tokens/status changed (dynamic) |
| `LlmGroups.model` → `llm:model` | model lifecycle status changed |
| `LlmGroups.fetch` → `llm:fetch` | download progress changed |
| `LlmGroups.sessions` → `llm:sessions` | any session changed |
| `LlmGroups.any` → `llm:any` | catch-all |

Streamed token emissions are **throttled**: ≤ one emission per
`config.streamThrottle` (default 50 ms) on the session's group, with the
terminal status always flushed. Bind a streaming widget to `LlmGroups.gen(id)`.

## Recipes

```dart
// 1. Real local model via Ollama (OpenAI-style streaming over HTTP)
class OllamaLlmProvider implements LlmProvider { /* see example/ */ }
LlmBloc.withConfig(LlmConfig(provider: OllamaLlmProvider(model: 'gemma3:1b')));

// 2. Streaming widget — rebuilds only on this request's group
class GenView extends StatelessJuiceWidget<LlmBloc> {
  GenView(this.id, {super.key}) : super(groups: {LlmGroups.gen(id)});
  final String id;
  @override Widget onBuild(BuildContext c, StreamStatus s) =>
      Text(bloc.state.sessions[id]?.text ?? '');
}

// 3. Cancel mid-stream
llm.cancel('r1'); // session → cancelled, runtime stops decoding
```

## Failure modes

- Generate with no ready model → session `failed` immediately (no silent wait).
- Load OOM / bad format → `modelStatus: error`, reason in `state.error`; **no
  fallback model** is substituted.
- `ModelSource` checksum mismatch → corrupt file deleted + throw; never loaded.
- `embed()` without `embeddings` capability → `UnsupportedError`.
- load/unload while generating → refused with a loud `state.error`.

## Anti-patterns

- ❌ Asking the model for facts about specific places/people/events — small
  on-device models confabulate. Use retrieval (app-side RAG); the model
  synthesizes. The package keeps retrieval out of its domain on purpose.
- ❌ Binding a streaming widget to `llm:any` — use `LlmGroups.gen(id)`.
- ❌ Emitting per token — the bloc already throttles; don't add another path.
- ❌ A vendor-shaped bloc / glue package for a runtime — it's an `LlmProvider`.

## Invariants

- **One terminal emission:** done / cancelled / error all funnel to a single
  terminal session emission; the `sequential` queue never wedges on cancel.
- **Throttled streaming:** ≤ one emission per window per session; terminal
  always flushed; no text is lost when chunks coalesce.
- **No unverified weights:** a `ModelSource` verifies SHA-256 before present.
- **No silent fallback:** lifecycle failures are loud; no substitute model.

## See also

`SPEC.md` (full design + Glean Almanac phases) · `README.md` (narrative) · repo
`AGENTS.md` (framework) · `ROADMAP.md` decision #6 (why it's a feature bloc).
