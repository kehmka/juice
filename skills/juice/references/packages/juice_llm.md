---
card_schema: "1.0"
package: juice_llm
version: 0.5.0
requires:
  juice: ">=1.5.0"
updated: 2026-09-16
---

# juice_llm — AI card

> On-device LLM inference as a bloc: model lifecycle + streaming generation +
> embeddings behind a swappable `LlmProvider` runtime seam and a `ModelSource`
> acquisition seam. Private by construction (in-process, no telemetry). Read
> repo `AGENTS.md` for the Juice mental model + gotchas.

## Purpose

**Owns:** model-acquisition + runtime lifecycle, generation/embedding session
state, and the engine's concurrency contract (queue, lease, safe preempt,
wedge detection). **Does NOT own:** prompts / RAG / retrieval (app truth),
priority policy (a caller pattern, not a parameter), or the runtime (the
`LlmProvider` seam). A runtime is a provider impl, not a glue package.

## When to use

An open model (Gemma-class) running privately on device with a real state
machine: download-with-progress, load/unload, streaming generation as state,
embeddings, image/audio input. Token streaming as selective rebuilds, runtime
swappable (llama.cpp / Ollama / LiteRT / cloud).

## Install

```yaml
dependencies:
  juice_llm: ^0.5.0
```

## Construct

Default `EchoLlmProvider` (pure-Dart, no downloads) so it runs anywhere:

```dart
final llm = LlmBloc.withConfig(LlmConfig(
  // provider: EchoLlmProvider(),  modelSource: null (⇒ fetchModel errors),
  // initialModel + resolvePath + modelSource ⇒ init probes isPresent, auto-loads,
  // loadOptions: LlmLoadOptions(gpuLayers: 999, contextTokens: 4096, threads: null,
  //     projectorPath: null),  // 0.2.0: mmproj GGUF, app-acquired; enables image/audio
  // streamThrottle: 50 ms, maxRetainedSessions: 8,
  // teardownPatience: 8 s,                   // 0.4.0 wedge ceiling (Concurrency)
  // onEngineTrace: (line) => journal(line),  // 0.3.0 engine journal; null = silent
));
llm.loadModel(model);                  // Echo: straight to ready
llm.generate(LlmRequest(requestId: 'r1', messages: [LlmMessage.user('hi')]));
final vec = await llm.embed('text');   // if model supports embeddings
```

## Seams

```dart
abstract class LlmProvider {            // runtime; default EchoLlmProvider
  String get name;                      // diagnostics ('echo', 'ollama', …)
  Set<LlmCapability> get capabilities;  // {text, embeddings, vision, audio}
  Future<void> load(String modelPath, LlmLoadOptions options); // throws LlmProviderException
  Future<void> unload();
  Stream<LlmChunk> generate(LlmRequest request); // listener-cancel ⇒ MUST stop the runtime
  Future<List<double>> embed(String text);       // UnsupportedError if unsupported
  Future<void> dispose();
}
abstract class ModelSource {            // weights; NO default (config.modelSource = null)
  Stream<ModelFetchProgress> fetch(LlmModel model, String destinationPath); // verify sha256,
  Future<bool> isPresent(LlmModel model, String destinationPath);  // else delete + throw
  Future<void> delete(LlmModel model, String destinationPath);     // ModelChecksumException
}
FileModelSource(ModelFileSystem fs); // adopts on-disk weights only; missing file ⇒ StateError
```

## API

```dart
void fetchModel(LlmModel m); void loadModel(LlmModel m); void unloadModel();   // → Events
void generate(LlmRequest r); void cancel(String requestId); void evictSession(String requestId);
Future<List<double>> embed(String text); // rejects: StateError (no model) / UnsupportedError
bool get isGenerating; String? get activeRequestId;

// Resource layer — service code awaiting a completion directly (no session/state
// emissions). Serialized since 0.2.1; see Concurrency.
Future<GenerationOutcome> beginGeneration(LlmRequest r,
    {required void Function(LlmChunk) onChunk}); // never throws; errors arrive as kind: error
class GenerationOutcome { GenOutcomeKind kind; Object? error; } // kind ∈ {done, cancelled, error}
Future<String?> stopGeneration();    // end the ACTIVE stream → cancelled; returns its id or null
Future<bool> preemptAtSafePoint({    // 0.3.0 — true ⇒ engine free (cancelled / ended / wedged)
    bool Function(String requestId)? where, Duration patience = const Duration(seconds: 45)});
Future<EngineLease> acquireEngine(); // 0.2.2 — throws StateError when engineWedged
bool get engineLeased; bool get engineWedged;   // 0.2.2 / 0.4.0
class EngineLease { void release(); }           // idempotent; ALWAYS in a finally

LlmRequest({required String requestId, required List<LlmMessage> messages, LlmSamplingParams params});
LlmMessage.user(String content, {List<Uint8List> images, List<Uint8List> audio}); // audio: 0.2.0;
LlmMessage.system(String); LlmMessage.assistant(String);   // text-only models ignore both lists
LlmSamplingParams({temperature = 0.7, topP = 0.95, int? maxTokens, List<String> stop});
LlmChunk(String textDelta, {int tokens = 0, bool done = false});
```

## Events

| Event | Concurrency | Effect |
|---|---|---|
| `InitializeLlmEvent(config)` | concurrent | apply config; with `initialModel`+`modelSource`+`resolvePath`: probe `isPresent`, auto-load if present |
| `FetchModelEvent(model)` | droppable | download + verify; progress → `llm:fetch`; no source/`resolvePath` ⇒ `modelStatus: error` |
| `LoadModelEvent(model)` | sequential | load runtime; **refused while generating** (`state.error`, status unchanged) |
| `UnloadModelEvent` | sequential | free runtime; refused while generating |
| `GenerateEvent(request)` | sequential | stream a completion into a session (via `beginGeneration`) |
| `CancelGenerationEvent(id)` | concurrent | stop the ACTIVE stream out-of-band; no-op unless `activeRequestId == id` |
| `EmbedEvent(text)` | sequential | vector via the event's `result` future |
| `EvictSessionEvent(id)` | concurrent | drop a retained **terminal** session; active ones are left alone |

## State

```dart
class LlmState {                       // BlocState; LlmState.initial; bool get isReady
  LlmModelStatus modelStatus;          // absent|fetching|fetched|loading|ready|error
  String? activeModelId; double? fetchProgress; // progress 0..1 while fetching, else null
  Map<String, GenerationSession> sessions;      // requestId → session
  String? error;                       // loud lifecycle error (session errors live on the session)
}
class GenerationSession {
  String requestId; SessionStatus status; // queued|streaming|done|cancelled|failed
  String text; int tokens; String? error; bool get isTerminal;
}
```

`activeRequestId` / `isGenerating` / `engineLeased` / `engineWedged` are
**bloc getters, not state** — no group emits when they change.

## Rebuild groups

| Group | Emitted when |
|---|---|
| `LlmGroups.gen(id)` → `llm:gen:<id>` | that request's tokens/status changed (dynamic) |
| `LlmGroups.model` → `llm:model` | model lifecycle status changed |
| `LlmGroups.fetch` → `llm:fetch` | download progress changed |
| `LlmGroups.sessions` → `llm:sessions` | any session changed |
| `LlmGroups.any` → `llm:any` | catch-all (`LlmGroups.all` = the four static groups) |

Streamed token emissions are **throttled**: ≤ one emission per
`config.streamThrottle` (default 50 ms) on the session's group, with the
terminal status always flushed. Bind a streaming widget to `LlmGroups.gen(id)`.

## Concurrency

Every builder declares its mode since 0.5.0: `InitializeLlmEvent` /
`FetchModelEvent` → `droppable`; `LoadModel` / `UnloadModel` / `Generate` /
`Embed` / `EvictSession` → `sequential`; `CancelGenerationEvent` →
`concurrent` (it must run DURING the streaming generate; idempotent).

One runtime context ⇒ one live stream.

- **Serialized resource (0.2.1).** `beginGeneration` chains every call onto
  one generation tail: `GenerateEvent` (already `sequential`), direct awaiters
  and `acquireEngine` take fair FIFO turns.
- **Priority is a caller pattern (0.2.1).** Name lanes via `requestId`
  (`'well-3'`, `'chat-7'`), read `activeRequestId`, and end a background
  stream rather than wait — since 0.3.0 via `preemptAtSafePoint`.
- **Safe-point preempt (0.3.0).** `preemptAtSafePoint({where, patience})`:
  nothing active → `true`; `where` excludes the active id → `false`; already
  streaming → stop now → `true`; still prefilling → wait for the first chunk
  (or the stream's end), then stop → `true`; no chunk within `patience`
  (45 s) → leave it running → `false`; `engineWedged` → `true`, touching
  nothing. A mid-prefill cancel can wedge a native runtime; each chunk is a
  yield boundary, so cancel-after-first-chunk is prompt.
- **Non-blocking stop (0.3.0).** `stopGeneration` completes the outcome
  `cancelled` at once; the provider teardown (`sub.cancel()`) chains onto the
  queue tail — the *next* generation waits for it, the stopper never does.
- **Teardown ceiling (0.4.0).** A teardown still pending after
  `teardownPatience` (8 s) declares the engine **wedged**: the tail resolves
  and everything queued or arriving fails fast (Failure modes). No in-process
  recovery is attempted.
- **Late un-wedge (0.4.1).** If the wedging teardown *itself* later
  completes, `engineWedged` drops and the engine serves again. A different
  teardown completing lifts nothing.
- **Engine lease (0.2.2).** `acquireEngine()` waits for in-flight + queued
  work, then holds the runtime until `release()`; every `beginGeneration`
  meanwhile queues behind it. Lifetime-grained ownership for a caller driving
  the runtime's own session across turns (tool-loop chat). Nothing times a
  lease out.

`onEngineTrace` lines: `queue <id> (active=<id|-> leased=<bool>)` · `start <id>` ·
`first-chunk <id> +Nms` · `done <id> +Nms Ntok` · `error <id> +Nms Ntok: <e>` ·
`stop <id> (streamed=<bool>)` · `teardown <id> +Nms` [`(late — after wedge declaration)`] ·
`wedged <id> — teardown never returned (Ns)…` · `un-wedged <id> — …` ·
`refused <id> (engine wedged[, was queued])` · `preempt-wait <id> (streamed=<bool>)` ·
`lease-wait (active=…)` · `lease-held` · `lease-released` · `lease-refused (engine wedged[, was queued])`.

## Recipes

```dart
// 1. Real local model via Ollama (see example/lib/ollama_llm_provider.dart)
LlmBloc.withConfig(LlmConfig(provider: OllamaLlmProvider(model: 'gemma3:1b')));

// 2. Streaming widget — rebuilds only on this request's group
class GenView extends StatelessJuiceWidget<LlmBloc> {
  GenView(this.id, {super.key}) : super(groups: {LlmGroups.gen(id)});
  final String id;
  @override Widget onBuild(BuildContext c, StreamStatus s) =>
      Text(bloc.state.sessions[id]?.text ?? '');
}

// 3. Interactive ask over a background lane — preempt at a safe point, then queue
await llm.preemptAtSafePoint(where: (id) => id.startsWith('well-'));
final out = await llm.beginGeneration(
  LlmRequest(requestId: 'chat-$n', messages: [LlmMessage.user(q)]),
  onChunk: (c) => buf.write(c.textDelta));
if (out.kind == GenOutcomeKind.error) surface(out.error); // incl. 'engine wedged — restart required'

// 4. Multi-turn chat that owns the runtime's session for its lifetime
await llm.preemptAtSafePoint(where: (id) => id.startsWith('well-'));
final lease = await llm.acquireEngine();          // StateError if engineWedged
try { /* drive the runtime's own session API OUTSIDE beginGeneration */ }
finally { lease.release(); }                      // idempotent; forgetting it starves the app
```

## Testing

Headless: a scripted `LlmProvider` + `settle()`. `test/llm_bloc_test.dart`
has `FakeLlmProvider` (`scriptedWords`, `perToken`, `loadError`,
`generateError`, `cancelledOrder` recorded in the generator's `finally`),
`WedgedProvider` and `LateTeardownProvider`.

```dart
Future<void> settle([int ms = 30]) => Future.delayed(Duration(milliseconds: ms));
final bloc = LlmBloc.withConfig(LlmConfig(provider: fake,
    teardownPatience: const Duration(milliseconds: 120)));
bloc.loadModel(model); await settle(); expect(bloc.state.isReady, isTrue);
bloc.generate(LlmRequest(requestId: 'r1', messages: [LlmMessage.user('hi')]));
await settle(); bloc.cancel('r1'); await settle();
expect(bloc.state.sessions['r1']!.status, SessionStatus.cancelled);
await bloc.close();
```

## Failure modes

- Generate (event path) with no ready model → session `failed` immediately.
  `beginGeneration` does **not** check `isReady` — the provider throws and the
  outcome is `kind: error`.
- Load OOM / bad format → `modelStatus: error`, reason in `state.error`; **no
  fallback model** is substituted.
- `fetchModel` with no `modelSource`/`resolvePath` → `modelStatus: error`.
- `ModelSource` checksum mismatch → corrupt file deleted + throw; never loaded.
- `embed()` → future rejects: `StateError` (no model) / `UnsupportedError`
  (no `embeddings` capability); never a meaningless vector.
- load/unload while generating → refused with a loud `state.error`.
- **Wedged engine (0.4.0)** — once `engineWedged`: every queued and future
  `beginGeneration` completes fast with `GenerationOutcome(error, error:
  'engine wedged — restart required')` (event path: session `failed` with
  that text); `acquireEngine` throws `StateError('engine wedged — restart
  required')`, also for a lease already queued; `preemptAtSafePoint` returns
  `true`. Recovery is an app restart — or the 0.4.1 late un-wedge.

## Anti-patterns

- ❌ Asking the model for facts about specific places/people/events — small
  on-device models confabulate. Use retrieval (app-side RAG); the model
  synthesizes. The package keeps retrieval out of its domain on purpose.
- ❌ Binding a streaming widget to `llm:any` — use `LlmGroups.gen(id)`.
- ❌ Emitting per token — the bloc already throttles; don't add another path.
- ❌ A vendor-shaped bloc / glue package for a runtime — it's an `LlmProvider`.
- ❌ Blind `stopGeneration()` to jump the queue — mid-prefill it can wedge a
  native runtime. Use `preemptAtSafePoint`.
- ❌ `beginGeneration` while holding your own lease — it queues behind your
  own `release()` and deadlocks. The holder drives the runtime directly.
- ❌ A lease without `finally { lease.release(); }` — nothing times it out;
  every generation in the app starves (visible only via `engineLeased`).
- ❌ Retrying an `'engine wedged'` outcome in a loop — it fails fast until
  restart (or a late un-wedge). Surface it; don't spin.

## Invariants

- **One terminal emission:** done / cancelled / error all funnel to a single
  terminal session emission; the `sequential` queue never wedges on cancel.
- **Throttled streaming:** ≤ one emission per window per session; terminal
  always flushed; no text is lost when chunks coalesce.
- **No unverified weights:** a `ModelSource` verifies SHA-256 before present.
- **No silent fallback:** lifecycle failures are loud; no substitute model; a
  wedge says "restart", it never pretends to recover.
- **Only the active id is cancellable:** `cancel(id)` is a no-op for a queued
  `GenerateEvent`; once it starts it can be stopped.
- **Only the wedging teardown un-wedges** (0.4.1); engine flags emit on no group.
- **`close()` bypasses the ceiling:** it awaits the active stream's cancel and
  `provider.dispose()` directly.

## See also

`SPEC.md` (full design + Glean Almanac phases) · `README.md` (narrative;
Concurrency + The engine lease) · `CHANGELOG.md` · repo `AGENTS.md`
(framework) · `ROADMAP.md` decision #6 (why it's a feature bloc).
