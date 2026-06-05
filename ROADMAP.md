# Juice Package Roadmap

The canonical catalog of Juice packages — shipped and planned — with the
boundaries and rules that keep the family coherent. Each package is a foundation
bloc that owns exactly one domain.

## Design invariants

1. **One domain per bloc.** Each bloc owns a single "truth," with an explicit
   *does-not-own* so domains never overlap.
2. **Substrate vs. features.** `juice` (core) and `juice_storage` (local truth)
   are substrate — any bloc may depend on them directly. **Two *feature* blocs
   never depend on each other**; a pairing of two feature domains becomes a
   **glue package**.
3. **Vendor seams at the edge.** Anything touching a platform/SDK exposes a
   provider interface (the `AuthProvider` pattern) so the bloc never marries a
   vendor.
4. **Standard shape.** `FeatureBloc<FeatureState>`, immutable state + `copyWith`,
   events in → state out, use cases, intent-named rebuild groups, proper
   `close()`, singleflight where concurrency bites.

## Glue packages

A glue package wires two (or more) feature domains together — adapters only, no
new domain truth. Examples in code: see `juice_auth_network`.

**Naming (locked):** `juice_<provider>_<consumer>` — the bloc whose state is
*consumed*, then the consumer. `juice_auth_network` = AuthBloc state consumed by
FetchBloc; auth-driven route guards are therefore `juice_auth_routing`.

## Catalog

Legend: ✅ shipped · 📋 planned

### Substrate
| Package | Owns | Status |
|---|---|---|
| `juice` | bloc/event/use-case/scope/`StatelessJuiceWidget` | ✅ |
| `juice_storage` | local truth (hive/secure/prefs) | ✅ |

### Foundation services
| Package | Owns | Does NOT own | Status |
|---|---|---|---|
| `juice_network` | remote request/response | local cache substrate | ✅ |
| `juice_routing` | navigation / guards | who the user is | ✅ |
| `juice_auth` | identity / session | the transport | ✅ |

### Ambient signals (small blocs others consume)
| Package | Owns | Does NOT own | Status |
|---|---|---|---|
| `juice_connectivity` | reachability / online-offline | making requests | ✅ |
| `juice_lifecycle` | app foreground/background/resume | navigation, sessions | ✅ |

### Domain services
| Package | Owns | Does NOT own | Status |
|---|---|---|---|
| `juice_permissions` | grant state machine (granted/denied/permanent) | the capability itself | ✅ |
| `juice_notifications` | local + push delivery / inbox | the permission grant | ✅ |
| `juice_location` | geolocation stream | the permission grant | ✅ |
| `juice_media` | camera/picker/upload state | storage of bytes | ✅ |
| `juice_realtime` | persistent WS/SSE streams | one-shot HTTP | ✅ |

### Presentation services
| Package | Owns | Does NOT own | Status |
|---|---|---|---|
| `juice_theme` | appearance / dark mode | persistence (uses storage) | ✅ |
| `juice_i18n` | locale + translations | formatting policy | ✅ |
| `juice_forms` | field state + validation | submission transport | ✅ |
| `juice_flags` | resolved flags | the remote fetch (behind a `FlagsSource` seam) | ✅ |

### Glue packages
| Package | Bridges | Status |
|---|---|---|
| `juice_auth_network` | auth → network (token, refresh, cache isolation) | ✅ |
| `juice_auth_routing` | auth → routing guards | ✅ |
| `juice_network_connectivity` | connectivity → network (pause/resume on reachability) | ⏸ deferred |
| `juice_sync` | storage (+ injected transport/online) → offline outbox / mutation queue | ✅ |

> **Deferred: `juice_network_connectivity` — design with `juice_sync`.** It's a
> valid glue (a true state→behavior bridge: ConnectivityBloc online/offline →
> FetchBloc pause/resume), unlike the dropped `flags_network`. But offline-aware
> *reads* (this) and offline *writes* (`juice_sync`) are two halves of one
> problem — building this first would carve the offline boundary before `sync`
> is designed and likely re-cut it. Build it alongside `juice_sync`, or when a
> real app needs offline-aware fetching. Until then, gate requests on
> ConnectivityBloc state in-app.

> **Dropped: `juice_flags_network`.** A remote flag source is a vendor concern
> (LaunchDarkly / Firebase Remote Config / a plain endpoint) behind
> `juice_flags`'s `FlagsSource` seam — a provider impl, not a bridge between two
> bloc states. If flags ever need to ride `juice_network`'s `FetchBloc`
> transport specifically, *that* would justify a glue package — build it then,
> with a real consumer. Not speculatively.

> Permission→capability wiring is **not** a glue package. It's uniform and
> mechanical (watch one grant, set one flag), so it uses a generic
> `PermissionBinding` helper exported from `juice_permissions`. Capability blocs
> (notifications/location/media) expose a neutral `setPermissionStatus`; the user
> wires `PermissionBinding(permissions, JuicePermission.x, onStatus: …)`.

## Locked architectural decisions (2026-05-28)

1. **Permissions is a shared bloc.** `juice_permissions` owns grant state;
   capability blocs (location/media/notifications) react to it via a generic
   `PermissionBinding` helper (exported from `juice_permissions`), **not**
   per-capability glue packages — the wiring is uniform, so a callback helper
   beats N near-identical packages. (Revised 2026-05-28.)
2. **Sync is a feature bloc on substrate + seams (revised 2026-05-28, at build).**
   `juice_sync` owns real domain truth (the durable outbox + partitioned-FIFO
   flush state machine), so it is **not** glue. It depends only on `juice` +
   `juice_storage` (substrate) and takes the *transport* (`MutationExecutor`) and
   *online trigger* (`onlineSignal: Stream<bool>`) as **injected seams** — never
   depending on `juice_network`/`juice_connectivity` (features). The original
   "sync = glue over network+storage+connectivity" framing was wrong: a feature
   bloc can't be a feature-bloc dependency hub. This is the outbox
   `juice_network`'s SPEC deferred.
3. **Ambient signals are their own packages.** `juice_connectivity` /
   `juice_lifecycle` stay separate (single responsibility; sync, realtime, and
   network-offline all consume connectivity) rather than folding into network.
4. **Every *bespoke* cross-cutting pair is a glue package.** Rich, one-off
   integrations (auth↔network, auth↔routing) get a glue package. **Uniform,
   mechanical** bindings (permission→capability) instead use a generic helper
   (`PermissionBinding`) — minting near-identical packages is sprawl, not
   coherence. (Refined 2026-05-28.)

## Build order

**Phase 1 — signals + shared deps:** `juice_connectivity`, `juice_permissions`,
`juice_lifecycle`. ✅ **Complete.**

**Phase 2 — breadth wins:** `juice_theme`, `juice_i18n`, `juice_auth_routing`
(glue; both base blocs already exist). ✅ **Complete.**

**Phase 3 — capability tier:** `juice_notifications`, `juice_location`,
`juice_media` (each exposes `setPermissionStatus`, wired via `PermissionBinding`),
`juice_forms`, `juice_flags` (`FlagsSource` seam + local default; no network glue).

> `juice_forms` post-0.1 under consideration: first-class named field groups
> (single group rebuild key, group-level validity/reset) and an optional nested
> submit shape. v0.1 supports grouped sections by composing field rebuild groups.

**Phase 4 — hard / realtime:** `juice_network_connectivity`, `juice_realtime`,
then `juice_sync` last (concurrency / conflict resolution; needs connectivity +
storage + network mature).

## Per-package workflow

Each package follows the path `juice_auth_network` set: scope → SPEC → build
adapters/use-cases with tests → juice-pure example (see the "demonstrate Juice
in full" rule) → analyze + test + dry-run clean → commit → publish → tag
`<package>-v<version>`.

## Versioning & maturity

This family is a **personal toolkit**, not a product seeking adopters. So
`1.0.0` isn't a marketing milestone — it's a promise to *future-you* that the
public API (bloc surface, events, state, seam) won't churn under an app you've
built on it. That promise is earned by **use**, not by a date or a feature
count. Versions graduate through gates, not a schedule:

**`0.1.0` — Reviewed.** Ships here on day one.
- Docs complete (README, CHANGELOG, SPEC, example), tests green, dry-run clean.
- Coherence-audited against the design invariants above.

**`0.2.x` — Maturing.** API still free to break.
- Real friction found and fixed (e.g. an additive `withConfig`, a renamed
  group) lands here while breaking is still cheap.

**`0.9.0` — Dogfooded.**
- Used in at least one real app screen.
- The vendor seam actually swapped once (real impl + a fake/second impl) — proof
  the seam isn't theoretical.
- Any API friction from real use is resolved *before* committing to it.

**`1.0.0` — Committed.**
- One full app shipped on it with no API change needed across a dev cycle.
- No known design debt; the `does-not-own` boundary held under real pressure.
- You're willing to eat a `2.0.0` to ever break it again.

The substrate three (`juice` 1.x, `juice_storage` 1.x, `juice_routing` 1.x)
cleared these gates implicitly — they're used everywhere, which is *why* they're
1.x. Everything else is honestly pre-1.0 until an app proves it.
