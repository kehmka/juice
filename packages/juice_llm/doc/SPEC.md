# juice_llm Specification

> **Status:** 0.1.0 built 2026-06-11 (Reviewed gate) — bloc, seams, lifecycle,
> throttled streaming, and the pure-Dart `EchoLlmProvider` complete and fully
> tested headless; example proves the real-model path via Ollama. The embedded
> llama.cpp FFI runtime + real Gemma 4 weights are the next step (Glean Almanac
> Phase A). See §"0.1.0 as built" for what shipped vs. this design.
> **Package:** `juice_llm`
> **Primary Bloc:** `LlmBloc`

## Overview

On-device LLM inference as a first-class Juice domain: a model-lifecycle state
machine (absent → fetching → fetched → loading → ready → generating/streaming →
cancelled → unloaded) plus generation and embedding **sessions**, with the
runtime behind a vendor seam. The package's reason to exist: open-source models
(Gemma-class) running privately on the user's device, driven through a
comprehensive JuiceBloc — streaming tokens as state emissions with per-request
rebuild groups, lifecycle as events, concurrency as declared modes rather than
hand-rolled flags.

Privacy is structural, not a setting: inference happens in-process, the package
has no telemetry, and nothing user-generated can leave the device *through this
package* — the only network touch is fetching model weights.

## Domain boundary

- **Owns:** model acquisition state (download progress, checksum verification,
  presence on disk), runtime lifecycle (load/unload, readiness, capability
  discovery), and generation/embedding session state (queued / streaming /
  done / cancelled / failed, accumulated text).
- **Does NOT own:**
  - **Prompt or RAG composition** — what to say to the model is app truth (or a
    future glue package). This package never grows an opinion about what the
    model is *for*.
  - **Retrieval** — fetching Wikipedia/OSM/etc. context is app-side; see
    §Synthesis-not-recall.
  - **The runtime** — llama.cpp / MediaPipe / a remote endpoint live behind
    `LlmProvider`.
  - **Weight hosting/licensing** — models are fetched from a configured source;
    weights are never bundled into an app binary. The descriptor carries the
    license: Gemma 4 (2026-03-31) is Apache 2.0 — no acceptance gate needed —
    but earlier Gemma generations and other families have custom terms, so the
    acceptance UX (app-side) keys off `LlmModel.license`.

## Dependencies

`juice` (+ `juice_storage` optionally for small metadata; weight files live on
the filesystem via a path the consumer provides). **Not** `juice_network` —
model download is a `ModelSource` seam, the same reasoning that dropped
`juice_flags_network`: a fetch impl is a provider concern, not a bridge between
two bloc states. **Not** `juice_permissions` — no OS permission gates inference.

## Seams

### `LlmProvider` (vendor seam — the `AuthProvider` pattern)

```dart
abstract class LlmProvider {
  String get name;                       // 'llama_cpp', 'mediapipe', 'openai_compat'
  Set<LlmCapability> get capabilities;   // {text, embeddings, vision}

  /// Load weights into the runtime. Throws LlmProviderException on OOM /
  /// format mismatch — surfaced loudly, never retried silently.
  Future<void> load(String modelPath, LlmLoadOptions options);
  Future<void> unload();

  /// Stream a completion. The returned stream MUST respond to cancellation
  /// (listener cancel ⇒ runtime stops decoding — out-of-band, not queued).
  Stream<LlmChunk> generate(LlmRequest request);

  /// Embedding vector. Throws UnsupportedError if {embeddings} ∉ capabilities.
  Future<List<double>> embed(String text);

  Future<void> dispose();
}
```

Implementations (revised at build — see §"0.1.0 as built"):

0. **`EchoLlmProvider`** *(shipped, in the package)* — pure-Dart, zero-dep
   reference runtime: streams a reflective reply word-by-word, deterministic
   embeddings. The `StaticFlagsSource` analog — the runnable default and the
   seam-contract reference. Makes the example + tests work with no native code.
1. **`OllamaLlmProvider`** *(shipped, in `example/`)* — OpenAI/Ollama-style
   streaming over HTTP. The real-model path **today** with no FFI: `ollama
   serve` + a pulled Gemma tag. The seam-swap reference; lives in the example so
   the core package stays dependency-free (the `FlagsSource`-recipe convention).
2. **`LlamaCppProvider`** *(next step — Glean Almanac Phase A; design in
   `doc/FFI_APPROACH.md`)* — FFI over llama.cpp, GGUF weights, Metal on Apple
   Silicon: an *embedded* runtime with no server process, for app-store
   packaging. Recommended approach: wrap `llama_cpp_dart` in a companion
   package `juice_llm_llamacpp` (isolate-owned; the provider is a thin facade).
   The genuinely hard part (native build surface, a device); deferred from
   0.1.0.
3. **`MediaPipeLlmProvider`** *(future)* — Google's on-device LLM Inference API
   (Android/iOS), when mobile becomes the active dogfood target.

### `ModelSource` (acquisition seam)

```dart
abstract class ModelSource {
  /// Resumable fetch to [destinationPath]; emits progress. Implementations
  /// MUST verify [model.sha256] before reporting complete — a mismatch deletes
  /// the file and throws (never load unverified weights).
  Stream<ModelFetchProgress> fetch(LlmModel model, String destinationPath);
  Future<bool> isPresent(LlmModel model, String destinationPath);
  Future<void> delete(LlmModel model, String destinationPath);
}
```

Default: `HttpModelSource` (dio, HTTP Range resume, sha256 streaming verify).
`FileModelSource` for tests and sideloading.

### Model descriptor

```dart
class LlmModel {
  final String id;                  // 'gemma-4-e2b-it-qat-q4'
  final Uri source;
  final String sha256;
  final int sizeBytes;              // for download UX + disk preflight
  final Set<LlmCapability> capabilities;
  final int contextTokens;
  final String license;             // surfaced before first fetch (Gemma terms)
}
```

## State & groups

```dart
class LlmState {
  final LlmModelStatus modelStatus; // absent | fetching | fetched | loading | ready | error
  final String? activeModelId;
  final double? fetchProgress;      // 0..1 while fetching
  final Map<String, GenerationSession> sessions; // requestId → session
  final String? error;              // lifecycle error (load/fetch), loud
}

class GenerationSession {
  final String requestId;
  final SessionStatus status;       // queued | streaming | done | cancelled | failed
  final String text;                // accumulated
  final int tokens;
  final String? error;
}
```

Groups (intent-named, selective):
- `llm:model` — lifecycle status changed (gates "is the Almanac awake" UI).
- `llm:fetch` — download progress (throttled; see streaming discipline).
- `llm:gen:<requestId>` — one session's tokens/status (a streaming text widget
  binds exactly this; nothing else rebuilds).
- `llm:any` — catch-all.

## Events & use cases

| Event | Concurrency | Notes |
|---|---|---|
| `InitializeLlmEvent` | — | apply config, probe `isPresent`, optional auto-load |
| `FetchModelEvent` | `droppable` | progress → `llm:fetch`; checksum fail ⇒ delete + loud error |
| `LoadModelEvent` | `sequential` | **fails loud if sessions are active** (no load-under-generate) |
| `UnloadModelEvent` | `sequential` | same guard |
| `GenerateEvent` | `sequential` | one runtime context ⇒ requests queue in order; each gets a session immediately (`queued`) so UI can render the wait |
| `CancelGenerationEvent` | `concurrent` | different event type, so it runs *during* a generate; cancels via the provider stream (out-of-band) |
| `EmbedEvent` | `sequential` | shares the context with generate |
| `EvictSessionEvent` | `concurrent` | completed sessions are retained until evicted; consumers read then evict (bounded by `maxRetainedSessions`, default 8) |

**Streaming discipline:** provider chunks are coalesced before emission — at
most one state emission per ~50 ms (or every N tokens) per session, on that
session's group only, with a final unthrottled emission on terminal status.
Token-per-emission would melt the rebuild pipeline; this is the package's main
performance contract.

**Cross-event guard (documented, deliberate):** `sequential` is per-event-type,
so generate-vs-load overlap is prevented by an explicit state check
(fail-loud), not by a mode — same family of reasoning as juice_realtime's
connect/reconnect guard.

## Fail-loud rules

- Generate with no loaded model → session fails immediately with an explicit
  error. Never silently queue waiting for a model that was never requested.
- Checksum mismatch → file deleted + `modelStatus: error`. Never load
  unverified weights, never retry silently.
- `embed()` without the capability → `UnsupportedError`, surfaced.
- Provider load failure (OOM, bad format) → loud error state with provider
  detail; no fallback model is ever substituted silently.

## Synthesis, not recall (app guidance — normative for the README)

Small on-device models (1–4B) are competent at **synthesis, narration, and
summarization of text supplied in the prompt** and unreliable at **factual
recall about specific places, people, or events** — they confabulate fluently.
Apps MUST treat the model as a writer, not an encyclopedia: facts come from
retrieval (app-side RAG over citable sources), the user's own content, or not
at all. The package keeps retrieval out of its domain precisely so this
boundary stays visible in app code.

## Reference app: Glean's Almanac

Glean (the dogfood journal) drives the build, one independently-shippable
phase per capability — stopping after A still ships the package story:

Primary model candidate: **Gemma 4 E2B** (released 2026-03-31, Apache 2.0,
natively multimodal, QAT variants cut the on-device footprint; ~4 GB RAM
class). One model can carry phases A *and* D, which simplifies the arc —
benchmark against a smaller text-only GGUF (e.g. a Gemma 3 1B-class) during A
if E2B's footprint is heavy for the first cut.

- **A — the nightly gleaning note.** Gemma 4 E2B QAT (GGUF) via
  `LlamaCppProvider` on macOS/Metal. The Almanac writes a one-line reflection
  synthesized from *today's own entries* — zero recall surface, pure
  synthesis. Proves: fetch UX, lifecycle, streaming groups, cancel.
- **B — embeddings → semantic search.** EmbeddingGemma-class model; vectors
  stored app-side next to FTS; `EmbedEvent` is the only new surface.
- **C — place context (RAG).** App retrieves Wikipedia/Wikivoyage/OSM near the
  capture (coarse, rounded coordinates; cached region bundles when online);
  the Almanac narrates retrieved facts tied to the user's day. Grounded and
  citable; the bloc only generates.
- **D — multimodal.** "Something interesting about that picture" via the
  `vision` capability — with Gemma 4 E2B this is the *same* loaded model as A,
  so D becomes enabling a capability rather than shipping a second model.

## Risks (named up front)

- **FFI build surface** — llama.cpp per-platform compilation is the largest
  engineering unknown; macOS-first keeps phase A tractable.
- **Battery/thermal on mobile** — phase A is desktop; mobile defers to the
  MediaPipe provider with its own budget decisions.
- **Weight licensing** — descriptor carries `license`; the app surfaces an
  acceptance flow before first fetch when the license demands one (Gemma 4 is
  Apache 2.0 and doesn't; older generations / other families may).
- **Disk pressure** — GB-scale files; `sizeBytes` preflight + explicit delete
  path are part of 0.1.0, not later polish.

## Testing

Deterministic by construction: a `FakeLlmProvider` streaming scripted chunks
(with controllable timing, honoring cancellation via `async*`'s `finally`).
State-machine tests (17, all green headless): load → ready / unload → absent,
loud load failure, queue order under `sequential`, cancel mid-stream (terminal
`cancelled`, generator `finally` ran, partial text kept), generate-with-no-model
fail-loud, generation error → failed, load-under-generate refusal, embed
capability + no-model guards, session eviction cap, and throttled-emission
coalescing (20 tokens → < 12 emissions). The embedded-runtime integration smoke
(real GGUF) runs locally behind a flag, never in CI — it arrives with
`LlamaCppProvider`.

## 0.1.0 as built (reconciliation)

What shipped differs from the original draft in three honest, surfaced ways:

1. **Shipped runtime is `EchoLlmProvider` (pure Dart), not `OpenAiCompat`.**
   The draft had OpenAiCompat shipping at 0.1.0 as test double + seam-swap.
   Built reality: the package ships only the zero-dep `EchoLlmProvider` default
   (the `StaticFlagsSource` convention — vendor impls live in app/example code),
   tests use an in-file `FakeLlmProvider` (better determinism than an HTTP fake),
   and the real-model seam-swap is `OllamaLlmProvider` in `example/`. The
   embedded llama.cpp FFI runtime — the actual "on-device, no server" story — is
   the **next step**, not 0.1.0. *This means 0.1.0 proves the architecture and a
   real model via Ollama, but does not yet embed a model in-process.*
2. **Sessions appear when a generation starts executing, not at enqueue.** The
   draft said each queued request "gets a session immediately." Under
   `sequential`, a not-yet-started request has no use-case context, so its
   session is created when generation begins streaming. Consequence:
   **cancelling a still-queued (not-yet-started) request is not supported in
   0.1.0** — `cancel` targets the active stream; an unknown/finished id is a
   no-op. A pre-enqueue session-stub is deferred until an app needs it.
3. **Embeddings ride the event's own result-completer** (`EmbedEvent.result`),
   mirroring the family's `ResultEvent` shape, rather than a core
   `sendForResult` (which is `juice_storage`'s own facility, not a juice
   primitive).

Everything else matches the design: the seams, the lifecycle state machine, the
throttled per-request streaming, the fail-loud rules, and the
synthesis-not-recall boundary.

## Spec Version

0.2 — drafted 2026-06-11 (scope), reconciled to the 0.1.0 build same day.
