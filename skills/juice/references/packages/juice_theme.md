---
card_schema: "1.0"
package: juice_theme
version: 0.1.0
requires:
  juice: ">=1.4.0"
  juice_storage: ">=1.2.0"
updated: 2026-06-09
---

# juice_theme — AI card

> App theme **selection** (mode + named flavor) as a Juice bloc, persisted
> through a swappable `ThemePersistence` seam. Read repo `AGENTS.md` for the
> Juice mental model + gotchas.

## Purpose

**Owns:** `ThemeMode` (light/dark/system) + an optional named `flavor` key.
**Does NOT own:** `ThemeData`, or the resolved platform brightness under
`system` (read `MediaQuery.platformBrightnessOf` in the UI). Feed
`state.mode` to `MaterialApp.themeMode`; map `state.flavor` to your own themes.

## Install

```yaml
dependencies:
  juice_theme: ^0.1.0
  juice_storage: ^1.2.0   # for the default StorageThemePersistence
```

## Construct

`persistence` is optional: `null` = in-memory only (resets on restart). Default
impl `StorageThemePersistence` stores `mode`/`flavor` as `StorageBloc` prefs.
`withConfig` loads the saved selection (or `defaultMode`/`defaultFlavor`).

```dart
final theme = ThemeBloc.withConfig(ThemeConfig(
  persistence: StorageThemePersistence(storageBloc),  // null → in-memory only
  defaultMode: ThemeMode.system,
  defaultFlavor: null,
));
```

## Seams

```dart
abstract class ThemePersistence {
  Future<ThemeSelection?> load();           // null if nothing saved
  Future<void> save(ThemeSelection s);
}
// ThemeSelection(ThemeMode mode, {String? flavor})
```

`ThemeMode` is Flutter's own enum (re-exported from the barrel) — it's the exact
value `MaterialApp.themeMode` consumes, so it is not mirrored.

## API

```dart
void setMode(ThemeMode mode);   // explicit
void toggle();                  // flip light⇄dark (system → dark)
void setFlavor(String? flavor); // null clears it
```

## Events

| Event | Effect | Group |
|---|---|---|
| `InitializeThemeEvent(config)` | configure persistence; load saved or defaults | `mode`, `flavor` |
| `SetThemeModeEvent(mode)` | set mode + persist (no-op if unchanged) | `mode` |
| `ToggleThemeEvent` | flip light⇄dark (system → dark) + persist | `mode` |
| `SetFlavorEvent(flavor?)` | set/clear flavor + persist | `flavor` |

Each change emits, **then** persists via the seam (shared `ThemeEmit.commit`
mixin keeps state + storage in sync).

## State

```dart
class ThemeState extends BlocState {
  ThemeMode mode;     // default system
  String? flavor;     // e.g. 'ocean'
  bool get isDarkMode; bool get isLightMode; bool get isSystemMode;
}
```

`isDarkMode` means the mode is *explicitly* dark. For the resolved brightness
under `system`, read `MediaQuery.platformBrightnessOf(context)` in the UI.

## Rebuild groups

| Group | Emitted when |
|---|---|
| `ThemeGroups.mode` → `theme:mode` | mode changed (set/toggle/init) |
| `ThemeGroups.flavor` → `theme:flavor` | flavor changed (set/init) |

## Recipes

```dart
// 1. Root app bound to mode (rebuilds MaterialApp on mode change only)
class App extends StatelessJuiceWidget<ThemeBloc> {
  App({super.key}) : super(groups: {ThemeGroups.mode});
  @override Widget onBuild(BuildContext c, StreamStatus s) => MaterialApp(
    themeMode: bloc.state.mode, theme: lightTheme, darkTheme: darkTheme,
    home: const Home());
}

// 2. Flavor → ThemeData mapping (your domain)
ThemeData themeFor(String? flavor) => switch (flavor) {
  'ocean' => oceanTheme, 'forest' => forestTheme, _ => defaultTheme,
};

// 3. Toggle button
IconButton(icon: const Icon(Icons.brightness_6), onPressed: theme.toggle);
```

## Testing

Headless — fake the persistence, drive the bloc:

```dart
class FakePersistence implements ThemePersistence {
  ThemeSelection? stored;
  Future<ThemeSelection?> load() async => stored;
  Future<void> save(ThemeSelection s) async => stored = s;
}
final fake = FakePersistence()..stored = const ThemeSelection(mode: ThemeMode.dark);
final theme = ThemeBloc.withConfig(ThemeConfig(persistence: fake));
await settle();                              // Future.delayed(20ms)
expect(theme.state.mode, ThemeMode.dark);    // loaded on init
theme.setMode(ThemeMode.light);
await settle();
expect(fake.stored?.mode, ThemeMode.light);  // persisted
```

## Failure modes

- `null` persistence → in-memory only; selection resets on restart (by design,
  not an error).
- `load()`/`save()` errors propagate from the seam — wrap your persistence if
  you need a fallback (and surface it loudly, never silently).

## Anti-patterns

- ❌ Putting `ThemeData` in this bloc — it owns the *selection* key, not the
  rendered theme.
- ❌ Reading `isDarkMode` to decide colors under `system` mode — it's false;
  resolve brightness via `MediaQuery`.
- ❌ Binding the whole app to `ThemeGroups.flavor` if only the mode drives
  `MaterialApp` — bind to `mode`.

## Integrates with

- **juice_storage** — substrate; `StorageThemePersistence(storageBloc)` is the
  default persistence (direct dependency is sanctioned). Pass `null` to skip it.

## Invariants

- Init loads saved selection, else falls back to `defaultMode`/`defaultFlavor`.
- `setMode` is a no-op (no emit, no persist) if the mode is unchanged.
- `toggle` maps `system`/`light` → `dark`, `dark` → `light`.
- Emit happens **before** persist (`ThemeEmit.commit`) — UI updates immediately;
  storage trails.

## See also

`SPEC.md` (design depth) · `README.md` (narrative) · repo `AGENTS.md` (framework).
</content>
