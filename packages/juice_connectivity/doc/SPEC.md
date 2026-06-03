# juice_connectivity Specification

> **Status:** Implemented (shipping).
> **Package:** `juice_connectivity`
> **Primary Bloc:** `ConnectivityBloc`

## Overview

`juice_connectivity` is an **ambient-signal** foundation bloc: it owns the
device's network reachability and nothing else. It is the signal that
`juice_network_connectivity` (pause/resume fetch) and `juice_sync` (flush the
offline outbox) consume.

## Domain boundary

- **Owns:** online/offline `status` + active `ConnectionType`.
- **Does NOT own:** making requests, caching, or deciding offline policy. Those
  belong to consumers/glue.

## Dependencies

| Package | Why |
|---------|-----|
| `juice` | core bloc infrastructure |
| `connectivity_plus` | default provider's platform source |

No `juice_storage` — connectivity is ephemeral signal, nothing is persisted.

## Vendor seam

`ConnectivityProvider` is the swap point. The bloc depends on the interface, not
on `connectivity_plus`, which is what makes it testable without a device.

```dart
abstract class ConnectivityProvider {
  Stream<ConnectivitySnapshot> get changes; // interface-state stream
  Future<ConnectivitySnapshot> check();      // one-shot
  Future<void> dispose();
}
```

`ConnectivitySnapshot { ConnectionType type; bool? reachable }` — `reachable` is
`null` unless a provider actively probes the internet (interface-up ≠
internet-reachable). The default `ConnectivityPlusProvider` reports
interface-state only (`reachable == null`); active reachability is an optional
provider capability, deliberately off by default to keep the base bloc free of a
probe host and HTTP dependency.

## State

```dart
enum ConnectivityStatus { unknown, online, offline }
enum ConnectionType { none, wifi, cellular, ethernet, other }

class ConnectivityState extends BlocState {
  final ConnectivityStatus status;        // default: unknown
  final ConnectionType connectionType;    // default: none
  final DateTime? lastChangedAt;
  bool get isOnline; bool get isOffline;
}
```

**Status derivation:** `none` → offline; `reachable == false` → offline;
otherwise online.

## Events

| Event | Effect | Groups |
|-------|--------|--------|
| `InitializeConnectivityEvent(config)` | configure provider, start (debounced) listening, emit immediate initial reading | `connectivity:status`, `connectivity:type` |
| `ConnectivityChangedEvent(snapshot)` | internal — derive status, emit only on change | changed groups only |
| `CheckConnectivityEvent` | one-shot manual re-read | as above |

## Debounce

Subscription changes are debounced (default 500ms, configurable) so consumers
don't thrash on network flapping. The initial reading from `check()` is applied
immediately (undebounced) so state is available at once.

## Lifecycle

`startListening()` subscribes to `provider.changes`; `close()` cancels the
debounce timer + subscription and calls `provider.dispose()`.

## Testing

`ConnectivityBloc` is tested with a fake `ConnectivityProvider` driven by a
`StreamController` — transitions, debounce, status derivation, and `check()` all
run headlessly. The only device-touching code, `ConnectivityPlusProvider`, is a
thin mapping verified by inspection and a one-time on-device run.

## Spec Version

| Version | Date | Status |
|---------|------|--------|
| 1.0 | 2026-05-28 | Implemented |
