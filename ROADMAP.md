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
| `juice_power` | charging state / charge level / OS power saver | when it's acceptable to be expensive | ✅ 0.1.0 |

### Domain services
| Package | Owns | Does NOT own | Status |
|---|---|---|---|
| `juice_permissions` | grant state machine (granted/denied/permanent) | the capability itself | ✅ |
| `juice_notifications` | local + push delivery / inbox | the permission grant | ✅ |
| `juice_location` | geolocation stream | the permission grant | ✅ |
| `juice_media` | camera/picker/upload state | storage of bytes | ✅ |
| `juice_realtime` | persistent WS/SSE streams | one-shot HTTP | ✅ |
| `juice_analytics` | event/screen tracking + consent | the vendor SDK (a sink) | ✅ |
| `juice_paging` | paged/infinite-scroll list state | the transport (a fetcher) | ✅ |
| `juice_observability` | crash capture + breadcrumbs | the vendor SDK (a reporter) | ✅ |
| `juice_llm` | on-device inference lifecycle (model acquire/load/unload, generation + embedding sessions) | prompt/RAG composition, retrieval, the runtime (behind `LlmProvider`) | ✅ 0.4.1 |

### LLM runtime providers (impls of `juice_llm`'s `LlmProvider` seam — never in core)
| Package | Runtime(s) | Deps | Status |
|---|---|---|---|
| `juice_llm` ▸ `EchoLlmProvider` | pure-Dart reference (the zero-dep default) | none | ✅ in core |
| `juice_llm_cloud` | OpenAI · Anthropic · Ollama (HTTP+SSE, **opt-in off-device**) — one shared `HttpSseLlmProvider` base | `http` | 📋 recipe now → promote |
| `juice_llm_llamacpp` | embedded llama.cpp (on-device, GGUF/Metal, no server) | `llama_cpp_dart` | ✅ 0.2.3 |

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
5. **Responsiveness is not a package — use Flutter built-ins.** Breakpoints /
   size classes / adaptive layout are already covered reactively by `MediaQuery`
   + `LayoutBuilder`. A `juice_layout` bloc would only add value for app-wide
   canonical breakpoints, context-free size-class reads, and class-change (vs
   per-pixel) rebuilds — not enough to justify shadowing the framework. It is
   **not** theming (`juice_theme` owns appearance only), but it is intentionally
   left to Flutter. Revisit only if a concrete need for non-widget-tree
   size-class reads appears. (Decided 2026-05-28.)

6. **`juice_llm` is a feature bloc on substrate + injected seams (decided
   2026-06-11).** On-device LLM inference is real domain truth — a model
   lifecycle state machine (absent → downloading → loading → ready →
   generating/streaming → cancelled/unloaded) plus generation/embedding session
   state — exactly the shape a JuiceBloc owns. The *runtime* (llama.cpp,
   MediaPipe LLM Inference, a remote OpenAI-compatible endpoint) sits behind an
   **`LlmProvider` vendor seam** (the `AuthProvider` pattern); model
   *acquisition* (GB-scale resumable download + checksum) is behind a
   **`ModelSource` seam** — a provider concern like `FlagsSource`, **not** a
   glue package onto `juice_network` (same reasoning that dropped
   `juice_flags_network`; revisit only if a real consumer needs models riding
   `FetchBloc` specifically). The bloc does **not** own prompts, RAG
   composition, or retrieval — those are app-side (or future glue) so the
   package never grows an opinion about what the model is *for*. Scope doc:
   `packages/juice_llm/SPEC.md`. Reference app: Glean's "Almanac" (on-device,
   private — the journal never leaves the device).

7. **LLM runtimes live outside core, packaged by *dependency weight* — locked
   2026-06-11.** `juice_llm` core ships only the seam + the zero-dep
   `EchoLlmProvider` (the `StaticFlagsSource` convention). Every real runtime is
   an `LlmProvider` impl that lives outside core, split on one axis:
   - **Pure-HTTP runtimes → one shared package `juice_llm_cloud`** (OpenAI,
     Anthropic, Ollama, future Gemini/Mistral…), over a common
     `HttpSseLlmProvider` base. *One* package, not per-vendor: they carry no
     vendor SDKs (raw HTTP), are byte-identical across adopters, and a new API
     is a new class not a new package. A vendor's breaking API change is
     absorbed inside the package. (Kevin chose the single shared package over
     per-vendor isolation.)
   - **Native runtimes → their own package** (`juice_llm_llamacpp`) — forced by
     native build assets; can't be a recipe or live in core. See
     `packages/juice_llm/doc/FFI_APPROACH.md`.

   **Cloud is opt-in and off-device** — providers that leave the device are a
   deliberate choice, never a default (juice_llm's identity is private/on-
   device). **Sequencing:** providers live as `example/` recipes until
   dogfooded, then promote to the packages above (same path as the
   FlagsSource recipes; don't mint published surface speculatively). **Before
   1.0:** design **tool / function calling** — it extends `LlmRequest`
   (tool defs) and `LlmChunk` (a tool-call variant), the one change most likely
   to reshape the seam; committing 1.0 without it would force a 2.0. Integration
   matrix + layout: `packages/juice_llm/doc/PROVIDERS.md`.

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

**Phase 5 — intelligence:** `juice_llm` (SPEC drafted 2026-06-11), built in
dogfood lockstep with Glean's Almanac phases: **A** text synthesis over the
user's own entries (llama.cpp/GGUF on macOS — proves seam, bloc, streaming,
model lifecycle), **B** embeddings → semantic search, **C** RAG'd place context
(retrieval is app-side; the bloc only generates), **D** multimodal vision.
Primary model: **Gemma 4 E2B** (2026-03-31, Apache 2.0, natively multimodal,
QAT on-device variants) — one model carries A and D. Each phase is
independently shippable; stopping after A still ships the package story.

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

**The dogfood app exists: Glean** (github.com/kehmka/glean — an offline-first
personal field journal using the full family). Findings flow through its
`DOGFOOD.md` (find → fix in the package → publish → drop the workaround). First
cycle landed: pick sessions + local items (`juice_media` 0.4.0), awaitable
validate/submit (`juice_forms` 0.2.0), and the macOS keychain-entitlement docs
gap (`juice_storage`).

## Concurrency semantics

Juice runs same-type use cases **`concurrent`**ly by default: when an `execute()`
suspends at an `await`, another event of that type can run during the suspension.
`emitUpdate` sets `bloc.state` **synchronously** (`StateManager.emit` →
`_state = state`), so a read-modify-write with no `await` between the read and
the emit is atomic — but a read *before* an await, written after, races.

**Primary mechanism (juice ≥ 1.5.0): per-event `EventConcurrency` modes** on the
`UseCaseBuilder`:

- **`sequential`** — same-type events queue and run one-at-a-time to completion,
  in order. Use for events that mutate shared state; the read-before-await race
  is impossible.
- **`droppable`** — a same-type event arriving while one runs is dropped.
  Use for exclusive flows; replaces a hand-rolled guard flag.
- **`concurrent`** (default) — for genuinely independent events; follow the
  read-at-emit discipline above.

Before 1.5.0 the same outcomes were hand-rolled. **Adopted so far:**

- `juice_observability` 0.2.0 — `RecordError`/`AddBreadcrumb` → `sequential`;
  deleted the bloc-side `_breadcrumbs`/`_errorCount` accumulator workaround.
- `juice_media` 0.3.0 — `AcquireMediaEvent` → `droppable`; dropped the
  `state.picking` entry guard.
- `juice_connectivity` 0.2.0 — initialize/check → `droppable`, connectivity
  changes → `sequential`; overlapping-flow tests lock in the behavior.
- `juice_analytics` 0.2.0 — log/screen/user/consent → `sequential`,
  initialize/flush → `droppable`; ordering and coalescing tests lock in the
  behavior.
- `juice_auth` 0.3.0 — initialize/login/logout/refresh/expiry → `droppable`,
  user updates → `sequential`; removed the public refresh completer in favor of
  dispatcher-owned singleflight.
- `juice_flags` 0.2.0 — initialize/refresh → `droppable`, fetched updates,
  failures, and override mutations → `sequential`; gated-source coverage proves
  refresh coalescing.
- `juice_forms` 0.3.0 — initialization → `droppable`; field mutations,
  whole-form validation, submission, and reset → `sequential`; token-guarded
  per-field async validation stays intentionally `concurrent`. A gated handler
  test proves overlapping submissions serialize and both callers complete.
- `juice_i18n` 0.2.0 — initialization → `droppable`; explicit and system
  locale events enter one bloc-owned FIFO because concurrency modes are keyed by
  exact event type. Gated-source coverage proves global request ordering and
  exclusive translation loads.
- `juice_sync` 0.2.0 — initialize → `droppable`; enqueue / retry / discard /
  online-changed → `sequential`; flush stays `concurrent` WITH its single-owner
  guard (the re-run flag is missed-wakeup semantics `droppable` would lose).
  Modes are per exact type, so Retry↔Discard on one id is a documented,
  deferred cross-type window (a bloc-owned FIFO closes it; no consumer yet).
  Gated-store coverage proves all three.
- `juice_theme` 0.2.0 — initialize → `droppable`; mode/toggle/flavor →
  `sequential`, which orders the SAVES (state was already race-free: `commit`
  emits before it awaits) at the cost that a second change's emit waits behind
  the previous save. Gated-persistence coverage pins exactly that.
- **Family complete, 2026-09-16** — the three packages the #22 list called
  "already correct" had only declared the events that NEEDED a non-default
  mode; the rest were bare (= `concurrent`, undeclared). Now every builder in
  every package is explicit: `juice_media` 0.6.0 (init → `droppable`; the
  twelve item/upload/permission mutations → `sequential`, all atomic today —
  declarative), `juice_observability` 0.5.0 (init → `droppable`; setUser /
  setContext / setEnabled → `sequential`; gated-reporter test), `juice_llm`
  0.5.0 (init → `droppable`, gated-source test; evict → `sequential`; cancel
  → `concurrent` EXPLICITLY — its own doc comment prescribed it: it must run
  during the streaming generate, and the sign-off table's `droppable` was
  wrong across requests), and juice core 1.7.2's own `ScopeLifecycleBloc`
  (start → `sequential`; end → `concurrent` with its per-scope singleflight).
- `juice_lifecycle` 0.2.0 — initialization → `droppable`, lifecycle changes →
  `sequential`; burst coverage proves provider order is retained in the
  `previous`/current phase pair.
- `juice_location` 0.2.0 — initialization and one-shot reads → `droppable`,
  tracking/position/permission mutations → `sequential`; gated-source coverage
  proves duplicate in-flight reads are coalesced.
- `juice_network` 0.13.0 — initialization → `droppable`; requests remain
  intentionally `concurrent` under request-key coalescing and the global slot
  limiter; configuration, cancellation, cache, reset, and observability events
  → `sequential`. The 72-test suite locks in coalescing and concurrency limits.
- `juice_notifications` 0.2.0 — initialization → `droppable`; initialization
  and all platform-service mutations enter one cross-event FIFO; tap and
  permission updates → `sequential`. Gated coverage proves schedule/cancel-all
  order across event types.
- `juice_paging` 0.2.0 — initialize, refresh, load-more, and retry →
  `droppable`; delegated refresh/load-more dispatches are awaited. The shared
  loading guard remains for cross-event exclusion, with gated coverage proving
  duplicate load-more coalescing and refresh/load-more non-overlap.
- `juice_permissions` 0.3.0 — initialization/settings → `droppable`, batch
  prompts → `sequential`, independent checks and keyed individual prompts stay
  intentionally `concurrent`. Gated coverage proves both parallel distinct
  permissions and serialized/coalesced exclusive flows.
- `juice_realtime` 0.2.0 — lifecycle/loss flows → `droppable`, sends,
  establishment, and messages → `sequential`; the connect/reconnect shared
  guard remains across event types. Connection epochs reject stale results and
  callbacks; gated coverage proves disconnect and user-connect supersession.
- `juice_routing` 1.3.0 — initialization → `droppable`, reset/pop mutations →
  `sequential`, visibility hooks → `concurrent`; navigation stays intentionally
  `concurrent` so requests can replace its depth-one latest-wins queue. Gated
  coverage proves latest-wins navigation and FIFO reset commands.
- `juice_storage` 2.1.0 — every builder explicitly uses `concurrent`; mutations
  and resource lifecycle enter a bloc-wide FIFO, while read-only queries remain
  genuinely concurrent. Gated coverage proves both overlapping reads and that
  a delete cannot overtake a TTL write and leave stale expiration metadata.

**Deliberately NOT adopted** — the modes are *per-event-type*, but this guard
carries extra logic, so a mode would change behavior:

- `juice_sync` — `droppable` would drop a flush trigger that must still *run* to
  set the `_pendingFlushRequest` re-check (work enqueued mid-flush).

Keep their hand-rolled guards. (The `juice_notifications` `lastTap` sentinel is a
copyWith fix, unrelated to modes.)

### Known edge-case items (0.2.x — surface under dogfooding)

Low-severity concurrency edges, deliberately deferred (not data-loss in normal
flows; require fixing only if an app hits them):

- **`juice_forms`** — `validate()`/`submit()` compute errors from a value
  snapshot; editing a field *during* that async pass can stamp a stale error.
  (Field *values* are read fresh, so no value loss.)
- **`juice_flags`** — a manual `refresh` whose fetch overlaps a live `changes()`
  stream push can apply the older fetch last (last-writer-wrong-order on the
  `_fetched` layer).
- **`juice_sync`** — `close()` during an in-flight flush disposes the store
  between the executor await and the durable delete; add a post-await
  `isClosing` guard when hardening.

## Tier 0 — robustness (2026-09-26)  ✅ juice 1.9.0

From the post-1.8.1 review: the design was ahead of the ecosystem, the
verification behind it. Five items, all shipped in juice 1.9.0 (+ juice_sync
0.2.1, juice_network 0.13.1 earlier):

1. **Close fence** — emits after close are dropped + logged
   (`emission_after_close`); events refused from the start of close
   (`isClosing`, monotonic); memoized close; retry abandons a closed bloc.
2. **Lifecycle can't wedge** — leases bound to their instance; a throwing
   close() clears its entry and fails (not hangs) FeatureScope.end(); wiring
   inside the telemetry span.
3. **`UseCaseBuilder.typed`** — event/use-case mismatch is a compile error;
   wrong bloc fails at construction.
4. **Coverage 55.8% → 94.4%, gated at 90% in CI** (`tool/coverage_check.sh`).
   The new tests found ten more bugs (scope switch, JuiceAsyncBuilder ×3,
   aviator error leak, inline navigation emit, CancellableEvent equality,
   TimeoutSupport timer) — all fixed and pinned.
5. **Web/WASM** — `logger/web.dart` re-export; pana 160/160.

Open from it: the vendored `Bloc<Event, State>` base (`bloc.dart`,
`emitter.dart`, `bloc_support.dart`, `bloc_base.dart`,
`global_bloc_resolver.dart`) — exported, unused, excluded from the gate;
deprecate or remove in 2.0.0. Relay setup errors (StateRelay/StatusRelay
init against an unregistered or closed bloc) surface only as uncaught zone
errors — decide whether that is fail-loud enough.

## Teed up from the BlocSignal comparison (2026-08-21)

Five items stolen with pride from `BlocSignal` (Randal Schwartz's
bloc-on-signals bridge, reviewed at v1.0.1 the week it shipped). None are
migrations — BlocSignal solves the container layer and doesn't touch the
constellation; these are the parts worth having. Ordered by value.

### 1 · DevTools telemetry + lint tooling  ✅ phases 1–3
The gap that should sting: one week old, BlocSignal ships a DevTools
extension (trace panel, state diffs, leak alerts), a lint package with
quick-fixes, and a `dart:developer` telemetry observer. Juice's graft
point already exists: every use-case execution and emission funnels
through the logger/StatusEmitter seam. **Phase 1 (cheap):** a
`JuiceDevtoolsObserver` on that seam posting `dart:developer`
`postEvent`/Timeline spans — visible in stock DevTools with zero UI work.
**Phase 2:** a real extension panel (transitions timeline, state diff,
group-rebuild inspector — the groups vocabulary makes rebuild tracing
MORE explainable than signals' auto-graph). **Phase 3:** `juice_lint`
(use-case-per-file, no-cross-feature-deps, relay-not-listener — the
AGENTS.md idioms as analyzer rules). Home: `juice_observability` for the
observer; extension packaging rules may force a dedicated package —
decide at build.

**Phase 3 SHIPPED (juice_lint 0.1.0, 2026-08-21):** three custom_lint
rules — juice_generic_event, juice_mutable_state_field,
juice_behavior_in_state — scoped to package:juice base types, verified by
an expect_lint fixture suite (example/). The const-widget gotcha is
already a compile error, so no rule for it.

### 2 · Opt-in select-style rebuilds alongside groups  ✅ 2026-09-21 (juice 1.8.0)
Turned out to ALREADY EXIST as `JuiceSelector` / `selectWith` / `bloc.select`
(found by the 2026-09-16 comparison) — exported, documented under
doc/widgets/, used once in the root example, zero tests, absent from
AGENTS.md, and listening to the RAW stream so every emission on a bloc woke
every selector regardless of group. Kevin chose keep-and-fix (option 2 of
four). Now: a `groups` parameter on both widgets and both stream forms,
filtering through the same `denyRebuild` as every Juice widget BEFORE the
value comparison — exactly the positioning written below (groups = the
vocabulary; select = a leaf optimization inside a group's blast radius).
Two latent bugs fixed on the way: the first emission was passed
unconditionally (an equal first emission rebuilt once for nothing) and the
doc claimed a replay that `bloc.stream` never does; `selectWith` skipped the
comparison whenever `previous` was null (nullable projections re-emitted
every time). Pinned by stream + widget tests; AGENTS §3 gained the bullet.
The measurement gate below still stands for PROMOTING the selector in
doctrine beyond "hot cell" — this change only made the existing widget
stricter and honest.
Signals' headline: per-value rebuild precision, auto-tracked. The honest
Juice version is selector + equality, no dependency-graph magic: a
`SelectJuiceWidget<TBloc, T>` / `.select<T>((state) => value)` that
rebuilds only when the selected value changes by `==`. **Positioning
(the one-knob-per-purpose resolution):** groups remain the canonical
bloc-driven invalidation vocabulary — cross-widget, intent-named;
`select` is a leaf-widget optimization for hot cells (list rows, tickers)
inside a group's blast radius. Additive; no change to existing widgets.
Gate: a real rebuild-storm case in an app (Amoli's person grid or well
counters are candidates), measured before and after.

### 3 · `restartable` as a fourth EventConcurrency mode  📋
New same-type event supersedes the in-flight one (typeahead, search,
scrubbing). Dart can't kill an awaited future, so the honest semantics
are **emission fencing**: an epoch counter per event type; a superseded
run's `emitUpdate`s become no-ops, and an optional `isSuperseded` check
lets long loops bail early. Documented loudly: side effects already
performed are NOT rolled back — restartable fences state, not the world.
Gate: a real consumer (none of the 25 packages needed it in the
concurrency migration — that's the tell it ships only when an app asks).

### 4 · `==`-dedup as an emit option  ✅ (already in core)
ALREADY SHIPPED as `emitUpdate(skipIfSame: true)` — the audit for this
item found core already had exactly the proposed design: per-call (never
bloc-wide), comparing `newState == state`, logging `state_emission_skipped`
when it fires (the type the DevTools panel already renders). What item 4
actually needed was DISCOVERABILITY, not code: it was undocumented and its
behavior untested (the prior "coverage" only mocked the parameter away).
Done 2026-08-21 — real behavior tests (test/bloc/skip_if_same_test.dart,
incl. the value-equality precondition), plus AGENTS §4c and a core README
bullet. The `skipIfUnchanged` name in this note was never real; the field
is `skipIfSame`.

### 5 · The AI skill bundle, in-repo  ✅ (2026-09-15 — see the docket, item 6)
BlocSignal ships a Claude Code plugin + skill bundle in the repo
(marketplace manifests included) — architectural idioms as an installable
skill for coding agents. Juice already wrote the content: AGENTS.md
(relays not listeners, demonstrate-in-full, one-knob-per-purpose, the
concurrency semantics doc). Packaging it as `.claude-plugin/` +
`skills/juice/` is distribution, not authorship — any consumer repo (or
future contributor's agent) installs the idioms instead of rediscovering
them. Cheapest item on this list; also the only marketing Juice has ever
needed ("a personal toolkit" — but the skill travels with the code).

## Teed up from the ecosystem comparison (2026-09-16)

Five independent deep-dives — bloc, Riverpod, signals, the rest (MobX / redux
/ stacked / rearch / get_it / commands), and developer experience — against
the same baseline; every "Juice lacks" claim adjudicated against source.
Full synthesis, rejections, and the calibration of where Juice is ahead:
`doc/ECOSYSTEM_COMPARISON_2026_09.md`; raw reports with versions and URLs in
`doc/comparison/2026-09/`. The verdict in one line: the model is not behind;
the gaps are things re-derived per package, enforcement still in prose,
tooling hosts that moved, and explanation. Kevin picks; nothing below is
built without its gate.

**Corrections to this file, free:** (1) teed-up #2 below is ALREADY BUILT as
`JuiceSelector` / `selectWith` / `bloc.select` — untested, absent from
AGENTS.md, and outside the groups vocabulary (it maps the raw stream);
keep-and-fix or deprecate. (2) "an event that returns a value" exists four
ways in the family (core `ResultEvent` with no helper; storage's
`sendForResult`/`OperationResult`; forms' and permissions' completers) — a
no-parallel-paths violation; promote storage's trio to core. (3) AGENTS
gotcha to add: builders register once at construction, so a NEW
`UseCaseBuilder` needs hot restart. (4) `JuiceExceptionWidget` has no
release-mode gate — a doctrine call.

| # | Candidate | Cost | Gate | Raised by |
|---|---|---|---|---|
| A | Skill via pub's package-skills channel (`packages/juice/skills/juice-framework/`, emitted by sync_skill.sh; installs with `dart run skills@ get` into Claude Code / Cursor / Gemini / Cline / Copilot — verified on dart.dev) | S | `skills@ get` accepts the name on a scratch consumer | dx |
| B | Port `juice_lint` to Dart's official `analysis_server_plugin` (reports via `flutter analyze`; quick fixes) — closes the CLI limitation found dogfooding | M | docket-5 sentinel proof under the new host | dx |
| C | The lint rules the gotchas imply (stale-read-across-await ×3 reports, missing-concurrency-mode ×2, send-in-build, nullable-copyWith sentinel, lease-in-build, feature-bloc-dependency, public-state-field) — after B | M | expect_lint fixture per rule reproducing a documented incident; 0 false positives across 28 packages | bloc, riverpod, signals |
| D | `fix_data.yaml` for the three `@Deprecated` members | S | confirm the v2.0.0 removal list | dx |
| E | State hydration seam (`StatePersistence<TState>` + `hydrate`; storage default + fake; versioned FAIL-LOUD migration) | M | migrating theme + i18n must net-delete code | bloc, riverpod |
| F | `bindStream` on `BlocUseCase` (bloc's `emit.forEach`; five packages hand-roll listen+cancel; enabler for `restartable`) | M | migrate location + llm; `close()` bodies shrink under LeakDetector | bloc |
| G | `juiceTest` + dogfood `BlocTester` (exists, unused, sleeps 10 ms) | M | theme + sync ports delete `settle()` calls and assert groups | bloc, dx |
| H | `WaitingStatus.progress`; `isWaitingFor<TEvent>()` / `isRunning(Type)` / `lastFailure(Type)` | S | llm model acquire; permissions' `requestsInFlight` map deletable | riverpod, others |
| I | DevTools rebuild inspector + state diff + emission rate (`widget_rebuild` event from the accept path) | M | approve the event schema, measure overhead; build with the select measurement | riverpod, signals, dx, others |
| J | Stop re-subscribing on every parent rebuild (`JuiceWidgetState` builds the filtered stream in `build`) | S | widget test counting `listen()` | signals |
| K | Lease `linger` window on `register` | S | a measured cold re-entry in Amoli | riverpod |
| L | `BlocScope.whenReady/allReady` + test-only `override<T>()` | S | count ordered init awaits in the example apps first | others |
| M | `juice_feature` mason brick | M | regenerate notes_app's feature to zero diff; delete on first drift | others, dx |

`restartable` (#3) stays parked but is now validated by two external
implementations (bloc_concurrency's switchMap fence; BlocSignal 1.3.0's
generation token) — build to the text below when a consumer appears; F is
the enabler. A `lane` key for cross-type FIFO waits on a juice_sync
consumer (its Retry↔Discard window is the waiting defect).

## Work docket — cleanup while #2 and #3 wait (2026-09-02)

State at survey: 28 packages, `main` 5 commits ahead of origin, tree
clean. Items 1 and 4 above are done; #2 (select-rebuilds) and #3
(`restartable`) stay parked on their gates by decision. What remains is
integrity and distribution debt, ordered by priority.

### 1 · `juice_storage` version-integrity drift  🔴
Three commits (HiveGateway seam + one bounded retry on the stale-lock
cold boot + its pins) changed shipped behavior while the pubspec stayed
at `2.1.0` — and `2.1.0` is already on pub.dev with the OLD code. One
version number, two different packages. Amoli hit the stale-lock bug on
2026-09-01, so a consumer is waiting on this.
→ Bump to `2.2.0` (additive seam + new retry), `[2.2.0]` CHANGELOG entry,
publish. Do this BEFORE pushing so `main` is self-consistent.

### 2 · Push the unpushed commits
Five on `main` (storage seam/pins, juice_lint, item 4). Safe once #1 has
landed.

### 3 · `juice_observability 0.4.0` — committed, unpublished  🟡
pub.dev is at `0.3.1`; `0.4.0` is the DevTools-extension release. Publish
runs through `tool/publish.sh` (rebuilds the extension into the archive
via `.pubignore !build`). LIVE-VERIFIED 2026-09-15 against the
juice_observability example on macOS in real DevTools 2.57.0: extension
discovered from the path dep, enable prompt, then Timeline (48 events —
execution/completed pairs with ms durations, emissions with groups),
Blocs (per-bloc emission count, groups, last event, state summary),
Problems ("no problems — good") all populated from live button presses.
Two notes from the look: config.yaml says `version: 0.1.0` while the
package is 0.4.0 (DevTools shows "v0.1.0" in the panel header — align
before publish); and Problems is FRAMEWORK problems (use_case_error,
leaks, unhandled events), not the app's own reported errors — the two
recorded errors correctly show in Blocs' state summary, not Problems.

### 4 · `juice` README drift (1.7.2?)  🟡 decision
Item 4 added one line to the core README after `1.7.1` shipped, so the
pub.dev page is one line stale. Recommendation: let it ride and fold into
the next real core change rather than burn a version on a doc line.

### 5 · Dogfood `juice_lint`  ✅ 2026-09-02
Was built, `publish_to: none`, and wired into ZERO packages — none of the
three rules had ever fired on real code. Now wired into all five
`juice_examples` apps (custom_lint + juice_lint path dev deps, analyzer
plugin in analysis_options) and runnable as `melos run lint:juice` —
`flutter analyze` does not load analyzer plugins, so it is its own script.
Result: all five apps CLEAN, and all three rules proven live on real app
code by planted sentinels (a mutable field + a closure field in NotesState,
a generic event in settings_events — each tripped its rule under
`dart run custom_lint`, then reverted). Not added to the `ci` script — a CI
gate is a rule, decided separately.

What the validation established about the SURFACE (the pubspec's open
question): (a) `dart run custom_lint` is the runner — `flutter analyze`
loads the plugin (the analysis server spins the plugin isolate) but does
not report its diagnostics, custom_lint's documented CLI behavior, verified
by the same sentinel through both runners; (b) the IDE path (analysis
server + plugin, what VS Code/IntelliJ show) is UNTESTED from the CLI —
open notes_app in an IDE, plant a non-final field in NotesState, expect the
squiggle; (c) under a memory/time-restricted sandbox the plugin isolate is
SIGKILLed and `flutter analyze` reports "analysis server exited with code
-9" for every app carrying the plugin block — fine on a dev machine, a
resource note for any constrained CI runner running `melos run analyze`.
Publishing stays `none` until it has caught something real in a consumer
app; the surface is validated, the value is not yet.

### 6 · Item 5 above — the AI skill bundle  ✅ 2026-09-15
Shipped as a Claude Code plugin at the repo root: `.claude-plugin/plugin.json`
+ `marketplace.json` (CLI-validated) and `skills/juice/`. The skill is a
thin ROUTING layer (SKILL.md: trigger, workflow, which reference for which
task, the five things bloc intuition gets wrong as pointers) over copies
of the doctrine — `references/agents-guide.md` (AGENTS.md), `index.md`
(llms.txt), `packages/*.md` (all 24 AI cards), `juice/*.md` (core docs) —
produced by `tool/sync_skill.sh`, whose `--check` mode fails on drift
(`melos run skill:check`; NOT wired into `ci` — a gate is a decision).
Links inside the copies are rewritten to resolve within the bundle
(verified: 0 broken). Install: `/plugin marketplace add kehmka/juice`
then `/plugin install juice@juice`; the skill is `/juice:juice`. Untested
live: an actual install into a consumer repo and the skill's trigger rate
on real prompts — skill-creator's eval loop and description optimizer
are the follow-ups when the bundle has a first consumer.

### 7 · Versioning audit + the nine stale AI cards  ✅ 2026-09-15
Kevin's hunch ("many packages are behind in versioning") checked on five
axes across all 25 published packages: local vs pub.dev (all match), code
under lib/ changed since the version-bump commit (none — the storage
drift was a one-off), declared `juice` floor vs features actually used
(no floor is dishonest; nobody uses EntityStatuses/guardEntity/skipIfSame
yet), AI-card `version` vs pubspec, CHANGELOG top vs pubspec. Findings:
(a) ISSUES #22 is the real "behind" — see item 8; (b) NINE cards had
drifted from their package version, untracked anywhere, and the skill
bundle (item 6) had just started shipping them: juice_llm 0.1.0→0.4.1,
juice_observability 0.2.0→0.4.0 (also `requires` said 1.5.0 vs pubspec
1.7.0; the card knew nothing of DevtoolsJuiceLogger or the extension),
juice_storage 2.1.0→2.2.0 (the seam + retry), juice_media 0.4.0→0.5.0,
juice_llm_llamacpp 0.1.0→0.2.3, and one patch each on auth_network,
auth_routing, sync, theme. All nine refreshed against source (every
symbol grepped in lib/ before it went on a card; changelog-only perf
figures left out), `requires` mirrors pubspec on all nine, `updated`
2026-09-15. Minor, parked: juice_llm and juice_llm_llamacpp use
`## 0.4.1` CHANGELOG headings, the other 23 use `## [0.4.1] - date`.
Lesson banked in ISSUES #23: nothing checked card-vs-pubspec; the drift
was invisible until a human asked.

### 8 · ISSUES #22 — the concurrency-migration tail  ✅ 2026-09-15 (modes only, no FIFO — Kevin's call)
`juice_sync` and `juice_theme` predate EventConcurrency: bare builders
(silently `concurrent`), `juice: ^1.4.0`; `juice_auth_network` /
`juice_auth_routing` are the constraint-only tail. The 2026-09-15 read
sharpened the risk: sync's flush use case has a guard and re-checks
`bloc.state.pending` per item, but enqueue / discard / retry are unguarded
read-modify-writes on the queue across an await — the exact race the rule
exists for, in a durable mutation queue. Which mode each event gets is
doctrine, so the build started with a per-event table for sign-off. Reading
the code overturned two draft cells: flush stays `concurrent` WITH its guard
(the re-run flag is missed-wakeup semantics; `droppable` would drop the
trigger), and online-changed went `sequential` like every other signal in
the family. Per-type modes cannot serialize Retry against Discard; the
bloc-owned FIFO that would was judged against the same gate as
`restartable` — no consumer of juice_sync exists — and deferred, documented
in the card, CHANGELOG and builder comment. Shipped: juice_sync 0.2.0,
juice_theme 0.2.0 (with the property sequential actually has: a second
change's emit waits behind the previous save — the test pins it),
juice_auth_network 0.1.3 and juice_auth_routing 0.1.2 (floors only).

### Hygiene gate, every publish
Package tests green + `dart pub publish --dry-run`, and audit BOTH the
README and `example/lib/main.dart` — both freeze into the archive (the
1.7.0 → 1.7.1 stale-docs lesson). And the AI card: `melos run cards:check`
(`tool/check_cards.sh <pkg>`) — `doc/LLM.md`'s `version` and `requires` must
mirror the pubspec (ISSUES #23; its first run caught four real drifts,
including a card the day-before refresh had missed).
