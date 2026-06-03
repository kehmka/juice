# juice_lifecycle example

A one-screen demo of `LifecycleBloc`, built with Juice primitives only.

A `DemoLifecycleProvider` cycles `resumed → inactive → paused` every 2 seconds,
so transitions show without actually backgrounding the app — the same provider
seam the real `WidgetsLifecycleProvider` plugs into. The screen is a
`StatelessJuiceWidget` bound to the `lifecycle:state` group; state lives in the
bloc.

For a real app, swap the provider for the default:

```dart
LifecycleBloc.withConfig(LifecycleConfig()); // WidgetsLifecycleProvider
```

## Run

```bash
flutter run
```
