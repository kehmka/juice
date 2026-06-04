# juice_theme

App theme selection — mode + optional flavor — as a
[Juice](https://pub.dev/packages/juice) bloc, with optional persistence behind a
swappable seam.

[![pub package](https://img.shields.io/pub/v/juice_theme.svg)](https://pub.dev/packages/juice_theme)
[![License: MIT](https://img.shields.io/badge/license-MIT-purple.svg)](LICENSE)

## What it owns

The theme *selection*: `ThemeMode` (light/dark/system) and an optional named
`flavor` (e.g. `'ocean'`). It does **not** own the `ThemeData` — feed
`state.mode` to `MaterialApp.themeMode` and map `state.flavor` to your themes.

## Install

```yaml
dependencies:
  juice_theme: ^0.1.0
```

## Use

```dart
import 'package:juice/juice.dart';
import 'package:juice_theme/juice_theme.dart';

final theme = ThemeBloc.withConfig(
  ThemeConfig(persistence: StorageThemePersistence(storageBloc)),
);

class App extends StatelessJuiceWidget<ThemeBloc> {
  App({super.key}) : super(groups: {ThemeGroups.mode});

  @override
  Widget onBuild(BuildContext context, StreamStatus status) {
    return MaterialApp(
      themeMode: bloc.state.mode,
      theme: ThemeData.light(),
      darkTheme: ThemeData.dark(),
      home: const HomePage(),
    );
  }
}

// elsewhere: theme.toggle();  theme.setMode(ThemeMode.system);
```

## Persistence seam (and why it's testable)

`ThemeBloc` depends on the `ThemePersistence` interface, not on storage. The
default `StorageThemePersistence` stores the selection in `StorageBloc`
(SharedPreferences). Inject a fake in tests, or pass `persistence: null` for
in-memory only:

```dart
class FakeThemePersistence implements ThemePersistence {
  ThemeSelection? saved;
  @override Future<ThemeSelection?> load() async => saved;
  @override Future<void> save(ThemeSelection s) async => saved = s;
}
```

## State

| Field / getter | Meaning |
|----------------|---------|
| `mode` | `ThemeMode` — feed to `MaterialApp.themeMode` |
| `flavor` | optional named theme key |
| `isDarkMode` / `isLightMode` / `isSystemMode` | mode checks |

> For the *resolved* brightness under `system`, read
> `MediaQuery.platformBrightnessOf(context)` in the UI — the bloc owns the
> selection, not the platform reading.

## License

MIT License — see [LICENSE](LICENSE).
