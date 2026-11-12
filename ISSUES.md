# Juice Framework - Known Issues

This document tracks known issues, bugs, and areas for improvement in the Juice framework codebase.

---

## Critical Issues

### 1. ~~Invalid `dispose()` Method Signature~~ FIXED

**File:** `lib/src/bloc/src/juice_bloc.dart`, Lines 209-211

**Status:** Fixed - Changed to synchronous `void dispose() { close(); }`

---

### 2. ~~Unawaited Async Calls in Resource Cleanup~~ FIXED

**File:** `lib/src/bloc/src/bloc_scope.dart`, Lines 109, 128, 140, 152, 160

**Status:** Fixed - All calls now use `close()` (fire-and-forget pattern).

---

### 3. ~~BlocScope Calls `dispose()` Instead of `close()`~~ FIXED

**File:** `lib/src/bloc/src/bloc_scope.dart`

**Status:** Fixed - All `dispose()` calls replaced with `close()` calls.

---

## Medium Issues

### 4. ~~Unsafe Type Cast to Dynamic~~ FIXED

**File:** `lib/src/bloc/src/core/use_case_executor.dart`

**Status:** Fixed - Added `setBloc(JuiceBloc blocInstance)` method to UseCase class. The executor now calls `useCase.setBloc(context.bloc as JuiceBloc)` instead of `(useCase as dynamic).bloc = context.bloc`. The cast is now contained within the UseCase class with proper type safety.

---

### 5. ~~Race Condition in EventSubscription Initialization~~ FIXED

**File:** `lib/src/bloc/src/use_case_builders/src/event_subscription.dart`

**Status:** Fixed - Added `_isClosed` guard at start of `_initialize()` to prevent race condition when `close()` is called before the deferred microtask executes. Also fixed in `RelayUseCaseBuilder`.

---

### 6. ~~Forced Non-Null Access Without Safety Checks~~ FIXED

**File:** `lib/src/ui/src/widget_support.dart`

**Status:** Fixed - Replaced forced non-null access with safe null-coalescing pattern:
```dart
final groups = event?.groupsToRebuild;
if (groups == null || groups.isEmpty) return false;
```

---

### 7. ~~Inconsistent Default Groups in StatelessJuiceWidget Variants~~ FIXED

**File:** `lib/src/ui/src/stateless_juice_widget.dart`

**Status:** Fixed - Standardized all widget variants to use `groups = const {"*"}` as default:
- `StatelessJuiceWidget`: `{"*"}` (unchanged)
- `StatelessJuiceWidget2`: `{"*"}` (was `{}`)
- `StatelessJuiceWidget3`: `{"*"}` (unchanged)

All variants now consistently rebuild on all state changes by default.

---

### 8. ~~Unchecked Late Variable Access~~ PARTIALLY FIXED

**File:** `lib/src/bloc/src/use_case_builders/src/relay_use_case_builder.dart`, Lines 60-63

**Status:** Partially Fixed - The BlocLease system now provides:
- try-catch wrapper that throws explicit `StateError` on initialization failure
- Closed bloc checks before proceeding (`if (sourceBloc.isClosed || destBloc.isClosed)`)
- Proper lease cleanup in `close()` method
- Race condition guard (`if (_isClosed) return;`)

The `late` variables are still used but initialization failures now produce clear errors rather than cryptic "Late variable not initialized" crashes.

**Remaining:** Could convert to nullable types for full safety, but current implementation is acceptable.

---

## Low Priority Issues

### 9. ~~Missing Exception Context in Error Logging~~ FIXED

**File:** `lib/src/bloc/src/use_case_builders/src/state_relay.dart`

**Status:** Fixed - Added bloc type information to error messages in StateRelay and StatusRelay:
```dart
'Error in StateRelay<$TSourceBloc, $TDestBloc>'
'Error in StatusRelay<$TSourceBloc, $TDestBloc>'
```

---

### 10. ~~Silent Event Swallowing in EventDispatcher~~ FIXED

**File:** `lib/src/bloc/src/core/event_dispatcher.dart`

**Status:** Fixed - Added warning log when unhandled event fallback is used:
```dart
JuiceLoggerConfig.logger.log(
  'No handler registered for ${event.runtimeType}, using fallback handler',
  level: Level.warning,
);
```

---

### 11. ~~Unused `disposeAll()` Method~~ NOT AN ISSUE

**File:** `lib/src/bloc/src/bloc_dependency_resolver.dart`

**Status:** Not an issue - `disposeAll()` is actively used in tests for cleanup. The method is part of the `BlocDependencyResolver` interface and properly implemented in concrete classes.

---

### 12. ~~Verbose Inline Error Throwing Pattern~~ FIXED

**File:** `lib/src/bloc/src/juice_async_builder.dart`

**Status:** Fixed - Added helper getters to encapsulate the error throwing pattern:
```dart
T get _requiredInitial =>
    widget.initial ?? (throw ArgumentError('widget.initial must not be null'));

T get _requiredSnapshotData =>
    _snapshotNotifier.value.data ??
    (throw StateError('Snapshot data must not be null'));
```

---

### 13. ~~Ambiguous `_Disposable` Interface~~ FIXED

**File:** `lib/src/bloc/src/juice_bloc.dart`

**Status:** Fixed - Removed the private `_Disposable` interface. The `dispose()` method is now a standalone public method with documentation explaining its relationship to `close()`.

---

### 14. ~~UseCase Emit Functions Lack Event Context~~ FIXED

**File:** `lib/src/bloc/src/core/status_emitter.dart`

**Status:** Fixed - Added event type to logging context when emitting state changes:
```dart
_logger.log('Emitting $statusName', context: {
  ...
  'event': event.runtimeType.toString(),
});
```

---

## Test Coverage Gaps

### 15. ~~Missing Resource Cleanup Tests~~ FIXED

**File:** `test/bloc/resource_cleanup_test.dart`

**Status:** Fixed - Created comprehensive test suite covering:
- Bloc close/isClosed flag
- Stream subscription cleanup (onDone events)
- Stream stops emitting after close
- State preservation after close
- Nested bloc cleanup with BlocScope
- Leased bloc cleanup when last lease is released
- Multiple lease reference counting

---

### 16. ~~Missing EventSubscription Tests~~ FIXED

**File:** `test/bloc/event_subscription_test.dart`

**Status:** Fixed - Created comprehensive test suite covering:
- Event transformation and forwarding
- Clean close handling
- `when` predicate filtering
- Source bloc close handling
- Close-before-initialize race condition
- Transformer error handling (graceful recovery)
- Multiple rapid initialize/close cycles

---

### 17. ~~Missing RelayUseCaseBuilder Error Tests~~ FIXED

**File:** `test/bloc/relay_use_case_builder_test.dart`

**Status:** Fixed - Created comprehensive test suite covering:
- State change transformation and forwarding
- Clean close and idempotent close
- Stops relaying after close
- Source bloc close handling
- Transformer error handling (closes relay)
- Dest bloc close handling
- Close during initialization race condition
- Multiple relays on same source bloc

---

### 18. ~~Missing BlocScope Eviction Tests~~ FIXED

**File:** `test/bloc/bloc_scope_test.dart`

**Status:** Fixed - Created comprehensive test suite covering:
- Permanent lifecycle (persistence until endAll, individual end)
- Leased lifecycle (create on first lease, dispose on last release)
- Multiple leases keeping bloc alive
- Lease count tracking
- New instance creation after close
- Feature lifecycle (dispose when feature ends)
- Multiple blocs in same feature scope
- Scoped vs global bloc independence
- Registration validation (duplicate, missing)
- Async lease acquisition
- Diagnostics API
- Edge cases (closing during active use, mixed lifecycles)

---

## Documentation Gaps

### 19. Missing Late Variable Documentation

**Description:** Multiple `late` variables throughout codebase lack documentation about when they're initialized and the risks of accessing them before initialization.

**Files Affected:**
- `lib/src/bloc/src/use_case_builders/src/relay_use_case_builder.dart`
- `lib/src/bloc/src/use_case_builders/src/event_subscription.dart`

---

### 20. Missing Error Recovery Documentation

**Description:** No documentation on how to handle failures in:
- EventSubscription (what happens when source bloc closes?)
- RelayUseCaseBuilder (how to recover from relay errors?)
- BlocScope (what happens when resolution fails?)

---

### 21. Missing Lifecycle Documentation

**Description:** The relationship between `dispose()` and `close()` is not documented. Developers may not know which to call or when.

---

## Family-Wide Debt

### 22. ~~Packages predating `EventConcurrency` still declare no mode (and pin `juice: ^1.4.0`)~~ RESOLVED 2026-09-15 (modes only; FIFO deferred)

**Description:** `EventConcurrency` landed in juice 1.5.0 and AGENTS.md §4 now
calls a concurrency mode "the primary fix, not a hand-rolled guard." Every
package written before it still uses bare `UseCaseBuilder(...)` with no
`concurrency:`, which silently means `concurrent` — same-type use cases may
interleave across an `await`. Any of them doing read-modify-write on state has
the read-before-await race latent.

Their pubspecs also still say `juice: ^1.4.0`, so consumers can resolve a juice
that does not have the API these packages should be using.

Raised by Kevin 2026-07-25, after `juice_power` was built and the audit found
that faithfully copying `juice_connectivity`'s shape had copied the gap too.

**Packages affected (2):** `juice_sync`, `juice_theme`.

**Already correct:** `juice_llm`, `juice_media`, `juice_observability`,
`juice_power`, `juice_connectivity` 0.2.0, `juice_analytics` 0.2.0,
`juice_auth` 0.3.0, `juice_flags` 0.2.0, `juice_forms` 0.3.0,
`juice_i18n` 0.2.0, `juice_lifecycle` 0.2.0, `juice_location` 0.2.0,
`juice_network` 0.13.0, `juice_notifications` 0.2.0,
`juice_paging` 0.2.0, `juice_permissions` 0.3.0,
`juice_realtime` 0.2.0, `juice_routing` 1.3.0,
`juice_storage` 2.1.0.

**Constraint-only tail:** `juice_auth_network` and `juice_auth_routing` also
declare `juice: ^1.4.0`, but register no use cases. Raise them to `^1.6.0` in a
separate glue-package pass after their direct dependencies have migrated.

**Re-confirmed 2026-09-15** by a five-axis versioning audit of all 25
published packages (the only "behind" it found besides #23). Sharpened:
`juice_sync`'s flush use case has a guard and re-checks `bloc.state.pending`
before each item, but `enqueue` / `discard` / `retry` are unguarded
read-modify-writes on the queue across an `await` — the exact race AGENTS
§4 names, in a durable mutation queue. `juice_theme` has the same shape at
lower stakes (every use case awaits its persistence then reads state). Which
mode each event gets is doctrine: the build opened with a per-event table for
sign-off.

**Completed 2026-09-16:** the consistency scan found the "already correct"
packages had declared only the non-default events — 21 bare builders across
juice_media, juice_observability, juice_llm and core's ScopeLifecycleBloc.
All explicit now (media 0.6.0, observability 0.5.0, llm 0.5.0, juice 1.7.2);
see ROADMAP "Adopted so far".

**Resolved 2026-09-15:** juice_sync 0.2.0 and juice_theme 0.2.0 declare every
mode (see each CHANGELOG and card's Concurrency table); auth_network 0.1.3 and
auth_routing 0.1.2 raise the floor. Modes only: the bloc-owned FIFO that would
serialize Retry against Discard was judged against the same gate as
`restartable` — no consumer of juice_sync exists — and deferred; the window is
documented in the card, the CHANGELOG, and the builder comment. Reopen the FIFO
when a consumer can issue `retryFailed()` and `discard()` back-to-back.

**Per package:**
1. Bump `juice: ^1.6.0`.
2. Give every `UseCaseBuilder` an explicit mode — `sequential` for events that
   mutate shared state, `droppable` for exclusive flows (init, connect, flush,
   pick), `concurrent` only where events are genuinely independent, stated on
   purpose rather than by omission.
3. Note it in the CHANGELOG; it is a behaviour change, not a cleanup.

**Completed first: `juice_connectivity` 0.2.0** (2026-08-12). Initialization
and manual checks are `droppable`; connectivity changes are `sequential`; the
package requires `juice ^1.6.0`. Behavioral tests cover overlapping initialize
and check events.

---

### 23. ~~AI cards drifted from their package version, and nothing checked~~ RESOLVED 2026-09-16 (tool/check_cards.sh)

**Description:** `doc/ai-cards/TEMPLATE.md` requires a card's `version` to
mirror its pubspec ("if they drift, the card is stale — fix it"), but no
script, test, or publish step ever compared them. On 2026-09-15 NINE of 24
cards had drifted: `juice_llm` 0.1.0 vs 0.4.1 (four minors of engine-lease,
preemption, and wedge semantics absent), `juice_observability` 0.2.0 vs
0.4.0 (the card knew nothing of `DevtoolsJuiceLogger` or the extension, and
its `requires` said juice 1.5.0 vs pubspec 1.7.0), `juice_storage` 2.1.0
vs 2.2.0, `juice_media` 0.4.0 vs 0.5.0, `juice_llm_llamacpp` 0.1.0 vs
0.2.3, and a patch each on `juice_auth_network`, `juice_auth_routing`,
`juice_sync`, `juice_theme`. Invisible until a human asked — and the AI skill
bundle (`skills/juice/`, ROADMAP docket item 6) had just started shipping
the cards to consumer repos.

**Fixed 2026-09-15:** all nine refreshed against source (every symbol
grepped in `lib/` before it went on a card), `requires` mirrors pubspec on
all, `updated` set.

**Mechanism, 2026-09-16:** `tool/check_cards.sh` (`melos run cards:check`)
fails on any card whose `version` differs from its pubspec, any `requires`
entry that differs from the pubspec constraint (`^1.6.0` ↔ `">=1.6.0"`;
explicit ranges verbatim), or a juice-family dependency the card omits. A
published package with no card is reported, not failed (juice core's guide
is AGENTS.md by design). Proven to catch a planted mismatch — and on its
FIRST real run it found four more drifts the 2026-09-15 refresh had missed:
`juice_theme`'s card still said 0.1.1 / juice >=1.4.0 (the refresh script had
crashed before reaching it; 0.2.0 shipped with that stale card in its archive
— docs-only, fixed in tree, ships with the next theme publish), and
`juice_auth`, `juice_i18n`, `juice_network` had said `juice_storage
">=1.2.0"` since June while their pubspecs widened to `<3.0.0`. All four
fixed 2026-09-16. Wired into the one scripted publish path
(`juice_observability/tool/publish.sh`) and the ROADMAP hygiene gate; NOT in
`ci` — that is a decision, not a default.
Still parked: `juice_llm` and `juice_llm_llamacpp` use `## 0.4.1` CHANGELOG
headings where the other 23 use `## [0.4.1] - date`; a CHANGELOG-top check
would want one style first.

## Found in the November 2026 review and the 2.1 wave

### 24. ~~Six defects in published packages~~ FIXED in the 2.1 wave (unpublished as of 2026-11-10)

Each was confirmed by reading the code, pinned by tests, and fixed in one
commit.

| Package | Defect | Fixed in | Commit |
|---|---|---|---|
| `juice_auth` | A login cooldown that had run out never cleared: the next attempt armed another, and no attempt reached the provider again | 0.5.0 | `dc877ff` |
| `juice_auth_network` | The refresh strategy waited the full 30 s when the refresh failed before `isRefreshing` was ever set | 0.3.0 | `14ee728` |
| `juice_sync` | Flushes ran while offline and burned attempts into the dead letter | 0.3.1 | `d5cb3f2` |
| `juice_routing` | The initial path ran no guards, so a guarded home page was shown to anyone; `RedirectResult.returnTo` was dropped | 2.1.0 | `852e83d` |
| `juice_network` | `FetchConfig.maxCacheSize` never reached the cache manager | 0.15.0 | `028d55d` |
| `juice_network` | Two bearer tokens shared cached and in-flight responses; an `AuthInterceptor` without an identity provider was accepted | 0.15.0 | `028d55d` |

Still as they were, by decision at the time: juice_sync's `online`
defaults to true, so the window before the first signal counts as
online; juice_network's cache cap counts bytes written this session
only.

### 25. ~~Core: three silent or stuck paths~~ FIXED in juice 2.1.0

- **A bloc that closed after a result event's first status left
  `sendForResult` waiting out its timeout.** Found when
  `AuthBlocRefreshStrategy` was ported to one `sendForResult`. The wait
  now fails at the close with a `StateError` (`b81465c`).
- **`BlocScope.reset()` left every registration in place when a close
  threw.** It clears in a `finally` now (`b94ee39`). `endAll` does not:
  #27.
- **A `droppable` drop was silent.** It is recorded as `eventDropped`
  (`2e1210c`), as a replaced or cancelled `sendAfter` is.

### 26. ~~Adding a stored field to `JuiceTelemetry` tripled the cost of building one~~ FIXED in juice 2.1.0; the cause is OPEN

**Found:** the benchmark run before the 2.1 wave. A send with every
telemetry record built went 0.63 → 0.78 µs; the release-default send did
not move. A bisect put it at the commit that added three fields for
reactions, and a dummy field on the fast baseline showed that a
THIRTIETH stored field alone is enough (`benchmarks/RESULTS.md` §18).

**Fixed (`52674b2`):** the eight facts only a relay's, a subscription's
or a reaction's entry carries are held in one object beside the entry.
It stores 25 fields. `test/bloc/telemetry_record_shape_test.dart` counts
them in the source and fails past 29.

**Open:** why. A standalone `dart compile exe` of the same shape shows no
step between 29 and 32 fields; the Flutter AOT build of the benchmark app
does. Until that is understood the rule is the measured one: time
`benchmarks/lib/breakdown_main.dart` before adding a stored field to the
entry. Not re-measured on the pinned toolchain or on the phone.

### 27. `BlocScope.endAll()` leaves every registration in place when a close throws

**File:** `packages/juice/lib/src/bloc/src/bloc_scope.dart`

`endAll` awaits `Future.wait` over the closes and clears the registry on
the next line; a close that throws skips the clear. `reset()` had the
same shape and was fixed in 2.1.0 (#25). `endAll` was left as it was
because changing it was not asked for; it is the same defect.

### 28. `BlocScope.register` discards a second registration silently

**File:** `packages/juice/lib/src/bloc/src/bloc_scope.dart`

A second `register<T>` with the same lifecycle returns without a word and
drops the new factory ("idempotent"). A test that registers its own bloc
after an earlier test registered one keeps running against the first —
Amoli's suite carries a `BlocScope.reset()` with a comment saying so. A
different lifecycle does throw. Under the house rule a discarded factory
is a silent fallback: it should be loud, or there should be an explicit
`override` for tests (ROADMAP, "Not in this wave" item 2).

### 29. ~~`AuthBlocAuthGuard` treats a session still being restored as signed out~~ FIXED in juice_auth_routing 0.3.0 (unpublished as of 2026-11-10)

**File:** `packages/juice_auth_routing/lib/src/auth_bloc_auth_guard.dart`

The guard asks `authBloc.state.isAuthenticated`, which is true only for
`AuthStatus.authenticated`. `AuthState.initial` is `AuthStatus.unknown`,
so until a session restore finishes the guard answers "not signed in".
**This matters more from juice_routing 2.1.0**, where the initial path
runs the guard pipeline: an app that initializes routing before its
session restore has finished starts a signed-in user on the login page.
**Reproduced 2026-11-10** with the real blocs, the restore's provider
call held open (`packages/juice_auth_routing/test/cold_start_restore_test.dart`):
the user lands on `/login?returnTo=/` and stays there after the restore
succeeds, because a guard is asked on navigation only; with
`AuthBlocRoutingBridge` sending them back, the login page is shown first
and then home, at every cold start, for as long as the restore takes. An
app that awaits the restore before it builds routing starts on home and
never shows the login page (the same file). The guest guard reads the
same getter; the role guard reads `hasRole`, which is also false while
there is no user yet.

**Fixed 2026-11-10** (Kevin: "wait for the answer"). The three AuthBloc
guards await `authBloc.waitFor((s) => s.status != AuthStatus.unknown,
timeout: restoreTimeout)` before they read their predicate
(`restoreTimeout`, default 10 seconds, on each constructor). At a cold
start the initial navigation stays pending until the session is known,
and the login page is never shown to a signed-in user. A restore that
has not answered in time, or an `AuthBloc` that closes meanwhile, is not
caught: the guard throws and juice_routing refuses the navigation with a
`GuardExceptionError`. No guard falls back to "signed out". The test
file above now states that behaviour: the wait, a failed restore, the
timeout, a deep link to the login page, a role-guarded start, and a
close during the wait.

**Left as it is:** juice_routing's own `AuthGuard`, `GuestGuard` and
`RoleGuard` take plain callbacks and cannot wait. An app that wires them
to its own auth by hand has the same decision to make.

### 30. The family's tests hand-roll `settle()`; nothing outside the core uses the test harnesses

603 `settle()` calls across `packages/*/test`, each a real-clock sleep.
`juiceTest` and `juiceFlowTest` are used only in the core's own tests,
and every package card still teaches `settle()`, while `AGENTS.md` says
to prefer the harnesses. With a virtual clock in 2.1.0 the debounces,
backoffs and polls the family now owns through `sendAfter` can be tested
without waiting.

### 31. Tracked `pubspec.lock` files are stale, and drift on every repo-wide run

The lock files are committed and no wave has updated them (one records
`juice` at 1.7.2). `melos run analyze` or `melos run test` rewrites
thirty to forty of them, which then have to be reverted by hand before a
commit. Either stop tracking the lock files of packages (the usual
practice for a library; an app's example may keep its own), or commit
them with each wave.

### 32. Checks that exist and are not in CI; one gate that disagrees with itself

- `tool/check_cards.sh` and `tool/sync_skill.sh --check` are run by hand
  and by the one scripted publish path. CI runs neither (#23 left that as
  a decision).
- `melos.yaml`'s `coverage:juice` script gates at 90; CI gates at 99
  (`tool/coverage_check.sh 99`). The melos script is the stale one.

### 33. The same exported name in more than one package

`SetPermissionStatusEvent` is declared in juice_location, juice_media and
juice_notifications; `CacheStats` in juice_network and juice_storage. An
app that imports two of them unprefixed gets an ambiguous-name error.

### 34. `rollups/` holds pre-2.0 source concatenations

Ten files, none with a `concurrency:` in it — every builder in them
would fail to compile on 2.0.0. They are bait for anything that greps
the repository for an example, an AI agent included.

### 35. Reported by the November audit, not re-verified

Listed so they are not lost; each needs reading before it is believed. A
transient session-restore or refresh failure is treated as session
expiry and evicts to login (juice_auth); `permissionGranted` is written
and never read in three packages.

## Found by the review before publishing (2026-11-11)

Five independent reviewers read the 2.1 branch and the Amoli port before
anything was published. Each defect below was reproduced first.

### 36. ~~Per-send state kept per event instance~~ FIXED in juice 2.1.0 (unpublished)

The framework keeps a send's facts OFF the event, in Expandos keyed on the
instance. Two outlived the send: an instance that once JOINED a
singleflight flight, sent again later as a leader, was answered by the
dead flight (`event_dispatcher.dart`); and a reaction's hop depth stayed on
the instance, so the app sending it again was charged the old chain's depth
and could be refused. The join is cleared when a send leads; the depth is
released when the run it caused ends (an identity check keeps a depth a
later hop stamped meanwhile — without it, a ring sending one cached
instance escaped the bound). `test/bloc/reused_event_test.dart`.

**Deferred by ruling:** R12 put the cause in an Expando, which makes an
event instance's identity part of the semantics. Per-run state carried by
the run (as `executionId` is) would remove the class. Kevin (2026-11-11):
2.1 ships the Expando with the fix above; run-carried facts come with
stage two of P4, which changes the same send path (#41).

### 37. ~~One throwing close hook stopped a close~~ FIXED in juice 2.1.0

A close runs hooks another bloc owns (a reaction's end records into the
destination's logger). One that threw left the bloc half-closed and the
waits behind it pending until their timeouts. Each hook is guarded and
recorded (`bloc_close_error`, `reason: 'a close hook threw'`).

### 38. ~~`juiceFlowTest` could pass when it should fail~~ FIXED in juice 2.1.0

Errors were counted once per error OBJECT for the whole flow (a const error
failing twice was one; claimed once, never again); under virtual time a
timer a use case left pending was dropped; work set off after the body —
a stream item still on its way, or set off by another bloc's close — ran
unseen. Also a `sendAfter` poll defeated the stuck rule (a hang until the
runner's timeout), and a timed-out flow left the probe, the logger and
BlocScope to every later test in the file. All fixed;
`test/testing/juice_flow_false_green_test.dart`. Still not seen, by design
and documented: a fire-and-forget timer on the REAL clock.

### 39. ~~The auth start: `unknown` for ever, and a refused start that spun~~ FIXED (juice_auth 0.5.0, juice_routing 2.1.0)

When reading the stored session threw and clearing the stale tokens threw
too, the restore ended without emitting: the status stayed `unknown`, and
the waiting guards (#29) refused every guarded route, the login page
included, with nothing to retry. The cleanup is guarded; the status always
leaves `unknown`, documented on `AuthStatus.unknown`. And
`JuiceRouterDelegate` showed its loading page for as long as the stack was
empty, so a refused start spun for ever: it shows `RoutingConfig.errorBuilder`
(new; a plain page naming the error without one).

**Release order:** routing 2.1.0 guards the initial path and would reach
apps on the published juice_auth_routing 0.2.0, whose guards read a
session still restoring as "signed out" — the #29 bug, in apps that never
upgraded. juice_auth_routing 0.2.1 (the 0.2 line, `juice_auth ^0.4.0`)
carries the waiting guards and ships with routing 2.1.0.

### 40. ~~`sendForResult`'s 30-second default against waits on a person~~ FIXED (docs; Amoli)

The default suits a network call, not a person: the documented permission
request timed out while the OS prompt was up, and Amoli's photo-picker Add
gave up on a big pick while the photographs still went into the draft (a
second tap added them again). The default stays; `AGENTS.md` and the
permissions docs say to size the timeout to the wait, and Amoli's picker
waits one preview bound per pick.

### 41. Smaller items — two FIXED in juice 2.1.0, one DEFERRED by ruling

- ~~A `joinKey` that throws comes back only as a failed future; nothing
  records it.~~ FIXED: recorded as `joinKeyFailed` (`join_key_error`,
  error level), and the send's future still fails with it.
- ~~`sendAndWaitResult`'s close path is documented as "fenced and will
  never succeed"; a non-restartable use case keeps running after close
  starts, so a save that completes is reported to its caller as a
  `StateError`.~~ FIXED in what it SAYS: the doc and the `StateError`'s
  message say the outcome is unknown, and that a value given after the
  close is not delivered. The behaviour stays: the wait cannot know.
- **Open, deferred by ruling:** imperative rings (a use case calling
  `otherBloc.send` back to its source) are unbounded and unsignalled; only
  reaction chains have the hop bound. Bounding them is stage two of P4 — a
  zone around every run so an imperative send carries a cause — which the
  bloc-to-bloc plan put out of scope, benchmark-gated (R7). Kevin kept R7
  for the 2.1 wave (2026-11-11): no such ring was found in Amoli or the
  family, and the zone costs every send. It returns with stage two of P4.

## Summary

| Priority | Count | Status |
|----------|-------|--------|
| Critical | 3 | All Fixed (#1-3) |
| Medium | 5 | All Fixed (#4-8) |
| Low | 6 | All Fixed (#9-14) |
| Tests | 4 | All Fixed (#15-18) |
| Docs | 3 | Open (#19-21) |
| Family debt | 2 | Resolved (#22, #23) |
| November 2026 review and the 2.1 wave | 12 | 4 Fixed (#24-26, #29; #26's cause open), 8 Open (#27, #28, #30-35) |
| The review before publishing | 6 | 5 Fixed (#36-40; #36's follow-up deferred to P4 stage two), 1 Partly fixed (#41: two of three; the third deferred under R7) |
| **Total** | **41** | **29 Fixed or resolved, 12 Open** |

---

## Fix Priority Recommendation

1. ~~**First:** Fix critical issues #1-3 (dispose/close cleanup)~~ DONE
2. ~~**Second:** Fix race conditions #5, #8~~ DONE
3. ~~**Third:** Fix remaining medium issues #4, #6, #7 (type safety, inconsistencies)~~ DONE
4. ~~**Fourth:** Add missing tests #15-18~~ DONE
5. ~~**Fifth:** Address low priority issues (#9-14)~~ DONE
6. **Finally:** Address documentation gaps (#19-21)
7. ~~**Family sweep:** #22 — concurrency modes + `juice: ^1.6.0` across the 2 remaining packages that predate 1.5.0, then the two constraint-only auth glue packages~~ DONE 2026-09-15
8. ~~**Card mechanism:** #23 — card-version-equals-pubspec check as a melos script + publish-gate step (cards themselves refreshed 2026-09-15)~~ DONE 2026-09-16
9. ~~**The 2.1 wave:** #24-26 — six published defects, three core paths, the telemetry entry's cost~~ BUILT 2026-11-10, unpublished
10. ~~**Before or with the 2.1 publish:** #29 — decide what `AuthBlocAuthGuard` does while the session is unknown, now that the initial path is guarded~~ DONE 2026-11-10: the guards wait for the answer
11. **Next:** #27 and #28 (one file, both loud-failure fixes), then #31 and #32 (repository hygiene), then #30 (the family's tests onto the harness)
