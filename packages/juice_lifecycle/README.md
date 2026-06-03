# juice_lifecycle

App lifecycle — foreground / background / resume — as a
[Juice](https://pub.dev/packages/juice) bloc, behind a swappable provider seam.

[![pub package](https://img.shields.io/pub/v/juice_lifecycle.svg)](https://pub.dev/packages/juice_lifecycle)
[![License: MIT](https://img.shields.io/badge/license-MIT-purple.svg)](LICENSE)

## What it owns

The app's `AppLifecycle` phase (`resumed` / `inactive` / `paused` / `detached` /
`hidden`) plus the previous phase. It does **not** decide what to do on a
transition — consumers react (e.g. re-check permissions on resume, reconnect a
socket).

## Install

```yaml
dependencies:
  juice_lifecycle: ^0.1.0
```

## Use

```dart
import 'package:juice/juice.dart';
import 'package:juice_lifecycle/juice_lifecycle.dart';

final lifecycle = LifecycleBloc.withConfig(LifecycleConfig());

class PrivacyShield extends StatelessJuiceWidget<LifecycleBloc> {
  PrivacyShield({super.key}) : super(groups: {LifecycleGroups.state});

  @override
  Widget onBuild(BuildContext context, StreamStatus status) {
    // Blur the app in the task switcher when not foreground.
    return bloc.state.isForeground ? const AppBody() : const BlurredScreen();
  }
}
```

`state.resumedFromBackground` is handy for "do X when the user comes back" —
re-reading permissions, refreshing data, reconnecting.

## State

| Field / getter | Meaning |
|----------------|---------|
| `lifecycle` | current `AppLifecycle` phase |
| `previous` | phase before the current one |
| `isForeground` | `resumed` |
| `isBackground` | `paused` or `hidden` |
| `resumedFromBackground` | just returned to foreground |

## The provider seam (and why it's testable)

`LifecycleBloc` depends on the `LifecycleProvider` interface, not on
`WidgetsBinding`. The default `WidgetsLifecycleProvider` wraps Flutter's
`AppLifecycleListener`; inject a fake in tests:

```dart
class FakeLifecycleProvider implements LifecycleProvider {
  final _ctrl = StreamController<AppLifecycle>.broadcast();
  AppLifecycle _current = AppLifecycle.resumed;

  @override Stream<AppLifecycle> get changes => _ctrl.stream;
  @override AppLifecycle get current => _current;
  @override Future<void> dispose() async => _ctrl.close();

  void emit(AppLifecycle p) { _current = p; _ctrl.add(p); }
}
```

## License

MIT License — see [LICENSE](LICENSE).
