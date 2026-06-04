# juice_theme example

A light/dark/system theme switcher, built with Juice primitives only.

Uses an `InMemoryThemePersistence` (the `ThemePersistence` seam) so the demo
runs with no storage plugin. The `MaterialApp` is a `StatelessJuiceWidget` bound
to the `theme:mode` group — changing the mode rebuilds the whole app via the
bloc, no `setState`.

For a real app, swap the persistence for the default:

```dart
ThemeBloc.withConfig(
  ThemeConfig(persistence: StorageThemePersistence(storageBloc)),
);
```

## Run

```bash
flutter run
```
