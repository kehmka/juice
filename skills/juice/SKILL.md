---
name: juice
description: The Juice Flutter framework (package:juice and every juice_* package — juice_storage, juice_network, juice_routing, juice_auth, juice_llm, juice_observability, and the rest). Use this skill whenever you write, review, refactor, test, or debug code that touches JuiceBloc, BlocUseCase, BlocState, EventBase, UseCaseBuilder, EventConcurrency, StatelessJuiceWidget, BlocScope, rebuild groups, emitUpdate/emitFailure, or a juice_* package — including when the user only says "add a bloc", "wire up state", "make this screen rebuild", or "add a use case" in a project whose pubspec depends on juice. Juice is barely represented in training data; without this guide the model writes plausible bloc code that fails at runtime (generic events that never match a builder, stale-read races under concurrent use cases, const widgets that do not compile). Consult it before emitting any Juice code, even for small edits.
---

# Juice

Juice is event-in / state-out with the logic isolated in use cases, one
class per event, and widgets that rebuild only when an emitted rebuild
group intersects theirs. It looks like other bloc libraries and behaves
differently in ways that matter: events are matched by exact runtime type,
same-type use cases run concurrently by default, state is an immutable
value with no behavior in it, and every vendor sits behind an injected seam.
Code written from general bloc intuition compiles and then misbehaves, so
this skill front-loads the guide the framework's own maintainers wrote for
AI models and routes you to the per-package card for anything specific.

## Workflow

1. **Confirm the project uses Juice.** Look for `juice:` or any `juice_*`
   entry in `pubspec.yaml`, or an import of `package:juice/juice.dart`.
   If neither is present, this skill does not apply.
2. **Read `references/agents-guide.md` in full the first time it comes up
   in a session.** It is about 280 lines: the mental model, the canonical
   package shape demonstrated end to end, widgets, the concurrency modes,
   telemetry, and the gotchas. Skimming it is how the runtime failures
   below get written.
3. **Working with a specific package?** Open its card at
   `references/packages/<package>.md` (for example
   `references/packages/juice_storage.md`). A card is 120 to 250 lines and
   is written so you can implement against the package without reading its
   source: construct, seams, API, events, state, rebuild groups, recipes,
   the testing pattern, failure modes, and anti-patterns. The catalog with
   one line per package is `references/index.md`.
4. **Before you emit code, re-read the Gotchas section of the guide** and
   check your draft against it. The list is short and every item is a
   mistake that compiles.
5. **After editing:** `flutter analyze` must be clean and `flutter test`
   green. If `juice_lint` is a dev dependency, `dart run custom_lint`
   catches three of the gotchas mechanically.

## What to read for which task

| Task | Read |
|---|---|
| New bloc, state, events, use cases | guide §2 (canonical shape) and §7 (naming) |
| A widget that should rebuild on a change | guide §3 and the package card's rebuild-groups table |
| Per-row loading or failure inside a list | guide §3 "Per-item async state", then `references/juice/ENTITY_STATUS_GUIDE.md` |
| Two events of the same type stepping on each other | guide §4 (concurrency modes and the read-after-await rule) |
| Choosing `sequential` / `droppable` / `concurrent` | guide §4; the card's Concurrency section if the package has one |
| Suppressing a no-op emit | guide §4c (`skipIfSame`, and why it needs value equality) |
| Integrating a vendor SDK (Firebase, Sentry, Dio, a platform API) | guide gotcha 7 (seam, not vendor import), then the package card's Seams section |
| Tracing what a bloc did | guide §4b (telemetry), `references/packages/juice_observability.md` |
| Testing a bloc | guide §6 and the card's Testing section (fake the seam, drive the bloc, assert on state and groups) |
| Which package owns a concern | `references/index.md` |

## The five things general bloc intuition gets wrong

Pointers, not restatements. Each is fully explained in the guide.

- **Events match by exact runtime type**, so a generic event never reaches
  its use case (guide gotcha 2).
- **`StatelessJuiceWidget` subclasses cannot be `const`**, and neither can
  a parent that forces it (gotcha 1).
- **Same-type use cases run concurrently by default.** A state read before
  an `await` is stale by the time you emit. Pick the concurrency mode on
  the `UseCaseBuilder` instead of hand-rolling a guard (§4, gotcha 3).
- **State holds data, not behavior**, and every field is `final` with
  changes through `copyWith`, with an `_unset` sentinel for nullable fields
  (gotchas 5 and 6).
- **The bloc never imports a vendor SDK.** It talks to a seam interface with
  a shipped default and a fake for tests (gotcha 7).

## About the references

Everything under `references/` is a copy, kept in sync from the Juice
repository by `tool/sync_skill.sh` there: `agents-guide.md` is the repo's
`AGENTS.md`, `index.md` is its `llms.txt`, `packages/*.md` are each
package's `doc/LLM.md` AI card, and `juice/*.md` are the core package's
design docs. Each card's front matter carries the package version it
documents; if the project's pubspec resolves a newer version than the
card, prefer the package's own changelog for what changed and treat the
card as the baseline.
