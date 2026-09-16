# Juice

> Juice is a lifecycle-aware Flutter application framework: use-case-driven blocs,
> scoped ownership, and targeted (group-based) rebuilds — plus a family of
> foundation packages that each own one domain behind swappable vendor seams.

Juice is not widely represented in training data. **Read `AGENTS.md` first** — it
is the dense AI guide (mental model, the canonical package shape, the
`EventConcurrency` modes, and the gotchas AI models reliably get wrong). Each
package then has a per-package **AI card** at `packages/<pkg>/doc/LLM.md`
(schema: `doc/ai-cards/TEMPLATE.md`), versioned to mirror its `pubspec`.

## Start here

- [AI Agent Guide](agents-guide.md): Juice mental model, canonical package shape, concurrency modes, gotchas — read before writing any Juice code.
- [Roadmap & decisions](https://github.com/kehmka/juice/blob/main/ROADMAP.md): full catalog, locked architectural decisions, the versioning/maturity ladder, concurrency semantics.
- [AI card schema](https://github.com/kehmka/juice/blob/main/doc/ai-cards/TEMPLATE.md): the per-package card format (card_schema 1.0).

## Substrate

- [juice](agents-guide.md): the core framework (`JuiceBloc`, `UseCaseBuilder`, `EventConcurrency`, `StatelessJuiceWidget`, `BlocScope`) — its AI guide is AGENTS.md.
- [juice_storage](packages/juice_storage.md): local persistence over Hive / prefs / secure / SQLite (await-based init; results via Futures).
- [juice_routing](packages/juice_routing.md): declarative navigation.

## Foundation

- [juice_network](packages/juice_network.md): HTTP via a Dio-backed `FetchBloc` (cache, coalescing, retry, interceptors).
- [juice_auth](packages/juice_auth.md): vendor-agnostic session / identity behind an `AuthProvider` seam.

## Ambient signals

- [juice_connectivity](packages/juice_connectivity.md): online/offline reachability signal.
- [juice_lifecycle](packages/juice_lifecycle.md): app foreground/background/resume.
- [juice_permissions](packages/juice_permissions.md): permission grant state + the generic `PermissionBinding` helper.
- [juice_power](packages/juice_power.md): charging state / charge level / OS power saver — the signal for "is it acceptable to be expensive right now".

## Domain & capability

- [juice_notifications](packages/juice_notifications.md): local notification delivery + tap routing.
- [juice_location](packages/juice_location.md): geolocation one-shot + tracking.
- [juice_media](packages/juice_media.md): camera/gallery acquisition + per-item upload state (+ remote items).
- [juice_realtime](packages/juice_realtime.md): persistent WebSocket/SSE with auto-reconnect.
- [juice_sync](packages/juice_sync.md): durable offline outbox / mutation queue.
- [juice_analytics](packages/juice_analytics.md): event/screen tracking behind a consent gate + fan-out sinks.
- [juice_paging](packages/juice_paging.md): generic paged / infinite-scroll list state.
- [juice_observability](packages/juice_observability.md): crash reporting + breadcrumbs with global error capture, the DevTools telemetry mirror, and the DevTools extension.
- [juice_llm](packages/juice_llm.md): on-device inference lifecycle — model acquire/load/unload, generation + embedding sessions, engine lease and wedge contract — behind an `LlmProvider` seam.
- [juice_llm_llamacpp](packages/juice_llm_llamacpp.md): the embedded llama.cpp `LlmProvider` (GGUF/Metal, multimodal via a projector, no server).

## Presentation

- [juice_theme](packages/juice_theme.md): appearance / dark mode (persists via storage).
- [juice_i18n](packages/juice_i18n.md): locale + translations.
- [juice_forms](packages/juice_forms.md): field state + sync/async validation with per-field rebuilds.
- [juice_flags](packages/juice_flags.md): feature flags / remote config behind a `FlagsSource` seam.

## Glue

- [juice_auth_network](packages/juice_auth_network.md): bridges auth → network (token injection, refresh, cache isolation).
- [juice_auth_routing](packages/juice_auth_routing.md): bridges auth → routing (route guards).
