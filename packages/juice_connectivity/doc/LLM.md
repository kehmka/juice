---
card_schema: "1.0"
package: juice_connectivity
version: 0.1.0
requires:
  juice: ">=1.4.0"
  connectivity_plus: ">=6.1.0"
updated: 2026-06-09
---

# juice_connectivity — AI card

> Network reachability as a bloc: online/offline + active `ConnectionType`,
> debounced, behind a swappable provider seam. An **ambient signal** other
> packages consume (e.g. `juice_sync` flush, fetch pause/resume). Read repo
> `AGENTS.md` for the Juice mental model + gotchas.

## Purpose

**Owns:** the device's reachability `status` (online/offline/unknown) + active
`ConnectionType`.
**Does NOT own:** making requests, caching, or offline policy. Those belong to
consumers/glue. Nothing is persisted (ephemeral signal).

## When to use

You need to react to connectivity — show an offline banner, gate a request, or
feed an `onlineSignal` to `juice_sync`. For the requests themselves use
`juice_network`; for the offline outbox use `juice_sync`.

## Install

```yaml
dependencies:
  juice_connectivity: ^0.1.0   # pulls connectivity_plus for the default provider
```

## Construct

The provider is **optional** — defaults to `ConnectivityPlusProvider` (interface
state only, no active reachability probe):

```dart
final connectivity = ConnectivityBloc.withConfig(ConnectivityConfig(
  // provider: MyReachabilityProvider(),     // optional; default = connectivity_plus
  debounce: const Duration(milliseconds: 500), // quiet period before a change applies
));
```

`withConfig` sends `InitializeConnectivityEvent`, which starts the debounced
subscription **and** does an immediate (undebounced) `check()` so state is
available at once.

## Seams

```dart
// Vendor seam. OPTIONAL (default ConnectivityPlusProvider).
abstract class ConnectivityProvider {
  Stream<ConnectivitySnapshot> get changes; // interface-change stream
  Future<ConnectivitySnapshot> check();      // one-shot current reading
  Future<void> dispose();
}

class ConnectivitySnapshot { final ConnectionType type; final bool? reachable; }
//  reachable == null  → interface-state only (the default provider never probes)
//  reachable == false → an active probe says the internet is UNREACHABLE → offline
```

Status derivation: `type == none` → offline; `reachable == false` → offline;
otherwise online. (Interface-up ≠ internet-reachable — only a probing provider
sets `reachable`.)

## API

```dart
ConnectivityProvider get provider;   // valid after init
void check();                        // one-shot manual re-read
Future<void> close();                // cancels debounce + subscription, disposes provider
```

## Events

| Event | Effect | Groups |
|---|---|---|
| `InitializeConnectivityEvent(config)` | configure provider, start (debounced) listening, emit immediate reading | changed groups |
| `ConnectivityChangedEvent(snapshot)` *internal* | derive status, emit only on actual change | changed groups only |
| `CheckConnectivityEvent` | one-shot manual re-read | changed groups only |

## State

```dart
class ConnectivityState extends BlocState {   // status: unknown | online | offline
  final ConnectivityStatus status;
  final ConnectionType connectionType;        // none | wifi | cellular | ethernet | other
  final DateTime? lastChangedAt;
  bool get isOnline; bool get isOffline;
  static const initial = ConnectivityState();
}
```

## Rebuild groups

| Group | Emitted when |
|---|---|
| `ConnectivityGroups.status` → `connectivity:status` | online/offline status changed |
| `ConnectivityGroups.type` → `connectivity:type` | connection type changed (wifi → cellular) |

A change emits only the groups that actually changed; an unchanged reading is a no-op.

## Recipes

```dart
// 1. Offline banner (selective rebuild on status only)
class OfflineBanner extends StatelessJuiceWidget<ConnectivityBloc> {
  OfflineBanner({super.key}) : super(groups: {ConnectivityGroups.status});
  @override Widget onBuild(BuildContext c, StreamStatus s) =>
      bloc.state.isOnline ? const SizedBox.shrink() : const _Banner();
}

// 2. Adapt to juice_sync's onlineSignal (the key ambient-signal recipe).
//    No package depends on the other — sync takes a Stream<bool>.
final online = connectivity.stream
    .map((_) => connectivity.state.isOnline)
    .distinct();
// → SyncConfig(onlineSignal: online, ...)

// 3. A reachability provider (active probe → sets snapshot.reachable)
class ReachabilityProvider implements ConnectivityProvider {
  final _ctrl = StreamController<ConnectivitySnapshot>.broadcast();
  @override Stream<ConnectivitySnapshot> get changes => _ctrl.stream;
  @override Future<ConnectivitySnapshot> check() async =>
      ConnectivitySnapshot(type: ConnectionType.wifi, reachable: await _ping());
  @override Future<void> dispose() async => _ctrl.close();
  Future<bool> _ping() async => /* HEAD a known host */ true;
}
```

## Testing

Headless — drive a fake provider's stream; no device:

```dart
class FakeConnectivityProvider implements ConnectivityProvider {
  final _ctrl = StreamController<ConnectivitySnapshot>.broadcast();
  var _current = const ConnectivitySnapshot(type: ConnectionType.wifi);
  @override Stream<ConnectivitySnapshot> get changes => _ctrl.stream;
  @override Future<ConnectivitySnapshot> check() async => _current;
  @override Future<void> dispose() async => _ctrl.close();
  void emit(ConnectivitySnapshot s) { _current = s; _ctrl.add(s); }
}

final fake = FakeConnectivityProvider();
final bloc = ConnectivityBloc.withConfig(
  ConnectivityConfig(provider: fake, debounce: Duration.zero),
);
await settle();
expect(bloc.state.isOnline, isTrue);
fake.emit(const ConnectivitySnapshot(type: ConnectionType.none));
await settle();
expect(bloc.state.isOffline, isTrue);
```

Use `debounce: Duration.zero` in tests so changes apply without waiting.

## Failure modes

- The default `ConnectivityPlusProvider` never sets `reachable` — interface-up
  is reported as **online** even if the internet is unreachable. For true
  reachability, supply a probing provider.
- A custom provider that throws from `check()`/`changes` surfaces through the
  use case as a bloc failure; `status` stays at its last value.
- No delivery guarantee on the change stream — it's a live signal, not a queue.

## Anti-patterns

- ❌ Treating the default provider's `online` as "internet reachable" — it's
  interface state only.
- ❌ Depending on `juice_connectivity` from `juice_sync`/`juice_network` wiring
  — pass the signal in via `onlineSignal` / a callback, keep them decoupled.
- ❌ Putting request/caching/offline-policy logic in here — it owns the signal only.
- ❌ Setting `debounce` very high on the money path — you delay the online→flush.

## Integrates with

- **juice_sync** — map `state.isOnline` → `onlineSignal` (Stream<bool>).
- **juice_network** (future glue) — pause/resume fetch on offline/online.

## Invariants

- The initial reading is applied **undebounced**; only subsequent stream changes
  are debounced (default 500ms) to absorb network flapping.
- Emits only the groups that changed; an identical snapshot is a no-op.
- `close()` cancels the debounce timer + subscription and disposes the provider.

## See also

`SPEC.md` (design) · `README.md` (narrative) · repo `AGENTS.md` (framework).
