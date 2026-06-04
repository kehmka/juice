# juice_theme Specification

> **Status:** Implemented (shipping).
> **Package:** `juice_theme`
> **Primary Bloc:** `ThemeBloc`

## Overview

`juice_theme` is a **presentation-tier** bloc owning the app's theme selection.
It owns the *selection*, not the rendering: the app maps the selection to
`ThemeData` and feeds `state.mode` to `MaterialApp.themeMode`.

## Domain boundary

- **Owns:** `ThemeMode` (light/dark/system) + an optional named `flavor`.
- **Does NOT own:** `ThemeData`, or the resolved platform brightness under
  `system` (read `MediaQuery.platformBrightnessOf` in the UI).

## Dependencies

| Package | Why |
|---------|-----|
| `juice` | core bloc infrastructure |
| `juice_storage` | default persistence (`StorageThemePersistence`) — substrate, direct-dep OK |

## Seam

`ThemePersistence` is the swap point: `load()` / `save(selection)`. The bloc
depends on the interface, not on storage — testable with a fake, or `null` for
in-memory only. Default `StorageThemePersistence` stores `mode`/`flavor` as
`StorageBloc` prefs strings.

`ThemeMode` is Flutter's own enum, re-exported from the barrel. (Unlike
`juice_lifecycle`, which mirrors `AppLifecycleState` to decouple from
`WidgetsBinding`, `ThemeMode` is the exact value `MaterialApp.themeMode`
consumes — mirroring it would only add friction.)

## State

```dart
class ThemeState extends BlocState {
  final ThemeMode mode;     // default: system
  final String? flavor;
  bool get isDarkMode; bool get isLightMode; bool get isSystemMode;
  static const initial = ThemeState();
}
```

## Events

| Event | Effect | Groups |
|-------|--------|--------|
| `InitializeThemeEvent(config)` | configure persistence, load saved (or defaults) | `theme:mode`, `theme:flavor` |
| `SetThemeModeEvent(mode)` | set mode + persist | `theme:mode` |
| `ToggleThemeEvent` | flip light⇄dark (system → dark) + persist | `theme:mode` |
| `SetFlavorEvent(flavor?)` | set/clear flavor + persist | `theme:flavor` |

State changes emit, then persist via the seam (shared `ThemeEmit` mixin).

## Testing

`ThemeBloc` is tested with a fake `ThemePersistence`: load-on-init, defaults
fallback, set/toggle/flavor + persistence, and null-persistence (in-memory) all
run headlessly.

## Spec Version

| Version | Date | Status |
|---------|------|--------|
| 1.0 | 2026-05-28 | Implemented |
