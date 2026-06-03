# juice_connectivity example

A one-screen demo of `ConnectivityBloc`, built with Juice primitives only.

A `DemoConnectivityProvider` cycles wifi → cellular → offline every 3 seconds,
so the app runs with **no device or network** — the same provider seam a real
adapter (`ConnectivityPlusProvider`) plugs into. The screen is a
`StatelessJuiceWidget` bound to the `connectivity:status` / `connectivity:type`
rebuild groups; state lives entirely in the bloc.

For a real app, swap the provider for the default:

```dart
ConnectivityBloc.withConfig(ConnectivityConfig()); // ConnectivityPlusProvider
```

## Run

```bash
flutter run
```
