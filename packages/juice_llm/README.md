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

One generation runs at a time — and since 0.2.1 the guarantee lives in
**`beginGeneration` itself**, which chains every call onto the generation
tail. It therefore holds for ANY caller: events through the `sequential`
`GenerateEvent` queue and service-layer code that awaits the method directly
both take fair FIFO turns against the single runtime context. (Before 0.2.1
only the event queue was ordered — two direct awaiters could race straight
into the provider. Harmless while nothing generated in the background;
a collision on every interactive call once an app enriches continuously.)

`CancelGenerationEvent` is `concurrent`, so it runs *during* a generation and
stops the runtime out-of-band by cancelling the provider stream. However a
stream ends — natural completion, error, or cancel — it funnels through one
terminal emission, so a session always reaches a terminal status and the
queue is never wedged.

Since 0.3.0, **`stopGeneration` never blocks its caller** on the provider's
teardown: an `async*` cancel only completes at a yield boundary, and a runtime
wedged mid-native-call has none — the old `await` there hung a caller forever,
outside every watchdog. The teardown chains onto the generation queue instead,
so the one-live-session guarantee still holds: the next generation waits until
teardown truly finishes, and a wedged teardown surfaces through *that* caller's
watchdog, loudly, rather than as a silent hang.

### Priority is the caller's pattern, not a parameter

FIFO is fair, but a user watching a spinner should not wait out a background
job. The package keeps priority OUT of the API; callers compose it from three
existing pieces — `requestId` (name your lanes), `activeRequestId` (see whose
turn it is), and `stopGeneration()` (end it):

```dart
// Background pass — its lane is visible in the requestId.
final outcome = await llm.beginGeneration(
  LlmRequest(requestId: 'well-$n', messages: [...]),
  onChunk: (c) => buf.write(c.textDelta),
);
if (outcome.kind == GenOutcomeKind.cancelled) {
  // Preempted by interactive work: leave this item undone; retry it later.
}

// Interactive ask — free the engine at the next SAFE point, background
// lanes only. NOT a blind stopGeneration(): a cancel that lands mid-PREFILL
// can wedge a native runtime (LiteRT) beyond recovery. preemptAtSafePoint
// cancels only once tokens stream — already decoding → now; still
// prefilling → right after the first chunk; no chunk within `patience` →
// it returns false and leaves the generation alone (your queued turn is
// the fallback, and your own watchdog stays the loud ceiling).
await llm.preemptAtSafePoint(where: (id) => id.startsWith('well-'));
final answer = await llm.beginGeneration(
  LlmRequest(requestId: 'chat-$n', messages: [...]),
  onChunk: (c) => out.write(c.textDelta),
);
```

## The engine lease

Serialization is turn-grained; some callers need **lifetime-grained**
ownership. A warm, multi-turn conversation (a tool-loop chat) drives the
runtime's own session API across many turns — and native runtimes hold ONE
live session per model, so any generation that runs between your turns
destroys the conversation's session ("Bad state: Session is closed"). The
lease closes that gap:

```dart
// Claim safely first (never mid-prefill), then own the engine for the
// conversation's LIFETIME. While held, every beginGeneration in the app —
// background enrichment included — queues behind release().
await llm.preemptAtSafePoint(where: (id) => id.startsWith('well-'));
final lease = await llm.acquireEngine(); // waits out in-flight + queued work
try {
  final chat = await runtime.createChat(...); // the runtime's session API,
  while (conversationOpen) {                  // driven OUTSIDE beginGeneration
    final reply = await chat.send(nextTurn);  // turns, tool calls, ...
  }
} finally {
  lease.release(); // ALWAYS in a finally — release() is idempotent, and an
}                  // unreleased lease starves every generation in the app.
```

Two disciplines make it safe in practice:

- **Visibility** — `llm.engineLeased` is the app-wide signal. Long-running
  background loops should check it in their own predicate and stand down,
  rather than piling blind work into the queue.
- **Release is the holder's job, loudly** — nothing times a lease out. A
  conversation that forgets its `finally` is a real bug the `engineLeased`
  flag makes visible, not something the package papers over.

The example app's **Lease demo** button walks the whole pattern live
(`example/lib/lease_demo.dart`): background lane preempted at a safe point,
lease held, a queued generation visibly waiting, release, the queue resuming.

## Observability

Every engine transition can be traced — `queue`, `start`, `first-chunk`,
`done`, `stop`, `teardown`, `lease-wait`, `lease-held`, `lease-released`,
`preempt-wait` — through one hook:

```dart
LlmBloc.withConfig(LlmConfig(
  onEngineTrace: (line) => journal.writeln(line), // e.g. an append-only file
));
```

A runtime that "degrades over time" is undiagnosable from a screenshot; an
append-only engine timeline turns the next wedge report into a timestamped
sequence you can read. The hook is synchronous, line-oriented, and silent
when unset.

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

`0.3.0` — production-proven in daily dogfood: an on-device journal app drives
this bloc over a LiteRT runtime (flutter_gemma) for continuous background
enrichment plus warm tool-loop conversations. The concurrency story matured
there under real load: the serialized generation queue (0.2.1), the engine
lease (0.2.2), and safe-point preemption, the non-hanging stop, and the engine
trace (0.3.0) each exist because a field failure demanded them — the CHANGELOG
tells those stories. Design record in `doc/SPEC.md`.
