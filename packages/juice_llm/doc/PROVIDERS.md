# Providers & integration

How you add an LLM to a Juice app, and where each runtime lives.

## The mental model

Integrate an LLM the way you integrate auth: a bloc + a provider seam.

| Auth | LLM |
|---|---|
| `AuthBloc` | `LlmBloc` |
| `AuthProvider` | `LlmProvider` |

You register `LlmBloc`, pick a runtime (an `LlmProvider`), and get streaming,
cancellation, and load-lifecycle as bloc state with per-request selective
rebuilds — no hand-rolled streaming/loading state in your widgets.

## The pitch: write once, swap runtime

Same widgets, same use cases, same tests underneath — the runtime is one line:

```dart
LlmBloc.withConfig(LlmConfig());                                     // Echo   — prototype
LlmBloc.withConfig(LlmConfig(provider: OllamaLlmProvider()));        // Ollama — local dev
LlmBloc.withConfig(LlmConfig(provider: LlamaCppProvider()));         // on-device — ship private
LlmBloc.withConfig(LlmConfig(provider: AnthropicLlmProvider(apiKey: k))); // cloud — ship frontier
```

Develop against Echo/Ollama; flip to the production runtime with one line. That
portability — and on-device as a *first-class* runtime, not a cloud
afterthought — is what `juice_llm` gives that a single-vendor client doesn't.

## Provider matrix

Choose on two axes: **where inference runs** × **dependency weight**.

| Provider | Runs | Deps | Use it for |
|---|---|---|---|
| `EchoLlmProvider` | — (pure Dart) | none | prototyping, tests, CI |
| `OllamaLlmProvider` | local server | `http` | local dev with a real model |
| `LlamaCppProvider` | **on-device** | native | shipping private inference |
| `OpenAiLlmProvider` / `AnthropicLlmProvider` | cloud | `http` | shipping frontier (opt-in) |

## Where the code lives (locked 2026-06-11)

Core ships only the seam + the zero-dep default. Every real runtime lives
outside core, packaged **by dependency weight**:

```
juice_llm                 core — bloc, LlmProvider/ModelSource seams, EchoLlmProvider
juice_llm_cloud           OpenAI · Anthropic · Ollama (HTTP+SSE, opt-in off-device)
juice_llm_llamacpp        embedded llama.cpp (on-device, native build assets)
```

- **`juice_llm_cloud` is one shared package, not per-vendor.** The HTTP runtimes
  carry no vendor SDKs (raw HTTP+SSE), are byte-identical across adopters, and
  share an `HttpSseLlmProvider` base — so a new API (Gemini, Mistral) is a new
  *class*, not a new package. deps: `juice_llm` + `http`.
- **`juice_llm_llamacpp` must be its own package** — native build assets can't be
  a recipe or live in core (it would drag a native toolchain into every app).
  deps: `juice_llm` + `llama_cpp_dart`. See `FFI_APPROACH.md`.
- **`EchoLlmProvider` stays in core** — the runnable, zero-dep default.

Layering is acyclic: provider packages depend *downstream* on `juice_llm`; core
never depends on them.

```dart
import 'package:juice_llm/juice_llm.dart';                  // bloc, seam, Echo
import 'package:juice_llm_cloud/juice_llm_cloud.dart';      // OpenAi/Anthropic/Ollama
import 'package:juice_llm_llamacpp/juice_llm_llamacpp.dart';// on-device
```

### Sequencing: recipe → promote

Today the HTTP providers live as **`example/` recipes** (copy-paste, clearly
labeled cloud = off-device) — the same path the FlagsSource recipes take, and
the maturity rule against minting published surface speculatively. They promote
into `juice_llm_cloud` (and llama.cpp into `juice_llm_llamacpp`) once dogfooded
and once the seam survives the tool-calling question below.

## Posture: on-device default, cloud opt-in

`juice_llm`'s identity is private/on-device. A cloud provider sends data off the
device — a supported, deliberate choice, **never a default**. Providers that
leave the device say so plainly; apps with sensitive data (journals, health,
notes) should default on-device.

## What the bloc does NOT own (so you don't look for it here)

- **Prompt templates / conversation history** — app state, or a future glue
  package. Keeping it out is what keeps `LlmBloc` honest.
- **Retrieval / RAG** — app-side. Compose `embed()` + your own retrieval +
  `generate()`. (See *synthesis, not recall* in the SPEC — a property of small
  on-device models; frontier cloud models relax it.)
- **Token cost / usage dashboards** — `LlmChunk.tokens` is exposed; a usage
  surface is a likely additive request, not core today.

## Before 1.0: tool / function calling

The one design question that gates the stable API. Today `generate()` yields
text deltas only. Tool use means `LlmRequest` carries tool definitions and the
stream can yield a *tool-call* chunk (not text) that the app executes and feeds
back — a real extension to `LlmRequest` and `LlmChunk`. It's the change most
likely to reshape the seam, and frontier + increasingly on-device models all do
it. **Design it before committing 1.0** — shipping the seam without it would
force a 2.0.

## See also

`README.md` (narrative) · `SPEC.md` (design + 0.1.0 reconciliation) ·
`FFI_APPROACH.md` (the on-device runtime) · repo `ROADMAP.md` decisions #6–#7.
