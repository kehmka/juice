# juice_connectivity

Network reachability as a [Juice](https://pub.dev/packages/juice) bloc —
online/offline and connection-type state behind a swappable provider seam.

[![pub package](https://img.shields.io/pub/v/juice_connectivity.svg)](https://pub.dev/packages/juice_connectivity)
[![License: MIT](https://img.shields.io/badge/license-MIT-purple.svg)](LICENSE)

## What it owns

The device's network reachability — `online` / `offline` and the active
`ConnectionType` (wifi/cellular/ethernet/…). It does **not** make requests or
decide what to do offline; consumers and glue packages (e.g. a future
`juice_network_connectivity`) react to it.

## Install

```yaml
dependencies:
  juice_connectivity: ^0.1.0
```

## Use

```dart
import 'package:juice/juice.dart';
import 'package:juice_connectivity/juice_connectivity.dart';

final connectivity = ConnectivityBloc.withConfig(ConnectivityConfig());

class OfflineBanner extends StatelessJuiceWidget<ConnectivityBloc> {
  OfflineBanner({super.key}) : super(groups: {ConnectivityGroups.status});

  @override
  Widget onBuild(BuildContext context, StreamStatus status) {
    if (bloc.state.isOnline) return const SizedBox.shrink();
    return const Material(
      color: Colors.red,
      child: Padding(
        padding: EdgeInsets.all(8),
        child: Text('You are offline', textAlign: TextAlign.center),
      ),
    );
  }
}
```

## The provider seam (and why it's testable)

`ConnectivityBloc` depends on the `ConnectivityProvider` interface, not on
`connectivity_plus`. The default `ConnectivityPlusProvider` is a thin adapter
over the plugin; swap in your own for custom reachability, or a fake in tests:

```dart
class FakeConnectivityProvider implements ConnectivityProvider {
  final _ctrl = StreamController<ConnectivitySnapshot>.broadcast();
  var _current = const ConnectivitySnapshot(type: ConnectionType.wifi);

  @override Stream<ConnectivitySnapshot> get changes => _ctrl.stream;
  @override Future<ConnectivitySnapshot> check() async => _current;
  @override Future<void> dispose() async => _ctrl.close();

  void emit(ConnectivitySnapshot s) { _current = s; _ctrl.add(s); }
}

final bloc = ConnectivityBloc.withConfig(
  ConnectivityConfig(provider: FakeConnectivityProvider()),
);
```

All of the bloc's behavior — transitions, debounce, status derivation — is
verified this way, no device required.

## State

| Field | Meaning |
|-------|---------|
| `status` | `unknown` / `online` / `offline` |
| `connectionType` | `none` / `wifi` / `cellular` / `ethernet` / `other` |
| `isOnline` / `isOffline` | convenience getters |
| `lastChangedAt` | when status or type last changed |

## Events

| Event | Effect |
|-------|--------|
| `InitializeConnectivityEvent` | configure provider + start listening |
| `CheckConnectivityEvent` | one-shot manual re-read |
| `ConnectivityChangedEvent` | internal — a new reading arrived |

## License

MIT License — see [LICENSE](LICENSE).
