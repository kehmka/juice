# juice_theme

> Canonical specification for the juice_theme companion package

## Purpose

Theme management with light/dark mode, dynamic theming, and persistence.

---

## Dependencies

**External:** None

**Juice Packages:**
- juice_storage - Persist theme preference

---

## Architecture

### Bloc: `ThemeBloc`

**Lifecycle:** Permanent

### State

```dart
class ThemeState extends BlocState {
  final ThemeMode mode; // light, dark, system
  final ThemeData lightTheme;
  final ThemeData darkTheme;
  final ThemeData currentTheme;
  final String? customThemeId;
  final Map<String, ThemeData> customThemes;
}
```

### Events

- `InitializeThemeEvent` - Load persisted theme preference
- `SetThemeModeEvent` - Switch light/dark/system
- `UpdateThemeEvent` - Apply custom theme modifications
- `LoadCustomThemeEvent` - Load theme by ID

### Rebuild Groups

- `theme:mode` - Mode changes
- `theme:current` - Active theme changes
- `theme:custom` - Custom theme list changes

---

## Open Questions

_To be discussed_
