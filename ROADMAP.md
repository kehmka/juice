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
| `juice_notifications` | local + push delivery / inbox | the permission grant | 📋 |
| `juice_location` | geolocation stream | the permission grant | 📋 |
| `juice_media` | camera/picker/upload state | storage of bytes | 📋 |
| `juice_realtime` | persistent WS/SSE streams | one-shot HTTP | 📋 |

### Presentation services
| Package | Owns | Does NOT own | Status |
|---|---|---|---|
| `juice_theme` | appearance / dark mode | persistence (uses storage) | ✅ |
| `juice_i18n` | locale + translations | formatting policy | ✅ |
| `juice_forms` | field state + validation | submission transport | 📋 |
| `juice_flags` | resolved flags / remote config | the fetch + cache | 📋 |

### Glue packages
| Package | Bridges | Status |
|---|---|---|
| `juice_auth_network` | auth → network (token, refresh, cache isolation) | ✅ |
| `juice_auth_routing` | auth → routing guards | ✅ |
| `juice_network_connectivity` | connectivity → network (pause/resume on reachability) | 📋 |
| `juice_flags_network` | network → flags (remote config fetch) | 📋 |
| `juice_sync` | network + storage + connectivity → offline outbox / mutation queue | 📋 |

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
2. **Sync is glue, not a base bloc.** `juice_sync` bridges
   network + storage + connectivity (dependency honesty over a standalone
   "outbox bloc"). This is the outbox `juice_network`'s SPEC deferred.
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
`juice_forms`, `juice_flags` (+ `juice_flags_network`).

**Phase 4 — hard / realtime:** `juice_network_connectivity`, `juice_realtime`,
then `juice_sync` last (concurrency / conflict resolution; needs connectivity +
storage + network mature).

## Per-package workflow

Each package follows the path `juice_auth_network` set: scope → SPEC → build
adapters/use-cases with tests → juice-pure example (see the "demonstrate Juice
in full" rule) → analyze + test + dry-run clean → commit → publish → tag
`<package>-v<version>`.
