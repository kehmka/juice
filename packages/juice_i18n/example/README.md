# juice_i18n example

A greeting + cart-count that switch between English and Spanish, built with
Juice primitives only.

Uses an in-memory `MapTranslationSource` so the demo runs with no assets or
storage. `MaterialApp` binds to `i18n:locale`; the body binds to
`i18n:translations` — switching language reloads strings and rebuilds via the
bloc, no `setState`. Shows `t()` with interpolation and `plural()`.

For a real app, swap the source/persistence for the defaults:

```dart
I18nBloc.withConfig(I18nConfig(
  source: AssetJsonTranslationSource(
    supportedLocales: const [Locale('en'), Locale('es')],
  ),
  persistence: StorageLocalePersistence(storageBloc),
));
```

## Run

```bash
flutter run
```
