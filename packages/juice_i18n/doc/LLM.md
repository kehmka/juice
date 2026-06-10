---
card_schema: "1.0"
package: juice_i18n
version: 0.1.0
requires:
  juice: ">=1.4.0"
  juice_storage: ">=1.2.0"
updated: 2026-06-09
---

# juice_i18n — AI card

> Reactive locale selection + translation lookup as a bloc: owns *which language*
> and *what the words are*, behind swappable `TranslationSource` and
> `LocalePersistence` seams. Read repo `AGENTS.md` for the Juice mental model +
> gotchas.

## Purpose

**Owns:** active `Locale`, follow-system, supported-locale resolution + fallback,
locale persistence, and `t()`/`plural()` lookup with `{placeholder}` interpolation.
**Does NOT own:** date/number/currency **formatting** (use `intl`); does not
replace gen-l10n — a custom source can wrap `AppLocalizations`.

## When to use

You need in-app language switching with reactive rebuilds and a remembered choice.
For formatting reach for `intl`; this owns string selection only.

## Install

```yaml
dependencies:
  juice_i18n: ^0.1.0
  juice_storage: ^1.2.0   # for the default StorageLocalePersistence
```

## Construct

`source` is **required**; `persistence` is optional (`null` = don't remember):

```dart
final i18n = I18nBloc.withConfig(I18nConfig(
  source: MapTranslationSource({
    'en': {'greeting': 'Hello {name}', 'cart.items.one': '1 item',
           'cart.items.other': '{count} items'},
    'es': {'greeting': 'Hola {name}', 'cart.items.other': '{count} artículos'},
  }),
  persistence: StorageLocalePersistence(storageBloc),  // SharedPreferences-backed
  fallbackLocale: const Locale('en'),
  followSystemByDefault: true,                          // first run with no saved choice
  // resolveSystemLocale: () => const Locale('es'),     // inject for tests
  // onMissing: (key) => '⟨$key⟩',                       // default: return the key
));
```

`withConfig` loads the initial locale: persisted choice → system (if
`followSystemByDefault`) → fallback.

## Seams

```dart
// WHERE strings come from. REQUIRED. Defaults: MapTranslationSource, AssetJsonTranslationSource.
abstract class TranslationSource {
  List<Locale> get supportedLocales;
  Future<Map<String, String>> load(Locale locale);   // flat key → string
  Future<void> dispose();
}

// REMEMBER the choice. OPTIONAL (null = none). Default: StorageLocalePersistence.
abstract class LocalePersistence {
  Future<LocaleChoice?> load();              // null = no saved choice
  Future<void> save(LocaleChoice choice);    // { Locale locale; bool followSystem }
}
```

Keys are flat (`'home.title'`); plurals use sub-keys (`'cart.items.one'` /
`.other`). The default `StorageLocalePersistence` stores prefs keys
`juice_i18n_locale` / `juice_i18n_follow_system`. **Strings are never copied into
storage** — only the *choice* is persisted; the source reloads strings each session.

## API

```dart
String t(String key, {Map<String, Object>? args});          // interpolates {name}
String plural(String key, int count, {Map<String, Object>? args}); // {count} auto-added
void setLocale(Locale locale);     // explicit (followSystem=false), persisted
void useSystemLocale();            // follow platform (followSystem=true), persisted
Locale resolveLocale(Locale want); // exact → language-only → fallback
Locale systemLocale();
```

`plural` picks `key.zero`/`key.one`/`key.other` by `count` (→ `key.other` → `key`).

## Events

| Event | Effect | Groups |
|---|---|---|
| `InitializeI18nEvent(config)` | configure, load initial locale (persisted → system → fallback); does **not** persist | `i18n:locale`, `i18n:translations` |
| `SetLocaleEvent(locale)` | resolve + load + persist (followSystem=false) | both |
| `UseSystemLocaleEvent` | resolve system + load + persist (followSystem=true) | both |

All three share the `I18nLoad` mixin: resolve → emit `isLoading` → load → emit → persist.

## State

```dart
class I18nState extends BlocState {
  final Locale locale;                       // → MaterialApp.locale
  final bool followSystem;
  final List<Locale> supportedLocales;
  final Map<String, String> translations;    // current locale only
  final bool isLoading;
  static const initial = I18nState();
}
```

## Rebuild groups

| Group | Emitted when |
|---|---|
| `I18nGroups.locale` → `i18n:locale` | active locale changed |
| `I18nGroups.translations` → `i18n:translations` | loaded strings changed (load start + finish) |

A locale switch emits `I18nGroups.all` (both); the loading flag flips
`translations` first.

## Recipes

```dart
// 1. Translated widget (rebuild when strings change)
class Greeting extends StatelessJuiceWidget<I18nBloc> {
  Greeting({super.key}) : super(groups: {I18nGroups.translations});
  @override Widget onBuild(BuildContext c, StreamStatus s) =>
      Text(bloc.t('greeting', args: {'name': 'Ada'}));
}

// 2. Feed MaterialApp (rebuild on locale change)
class App extends StatelessJuiceWidget<I18nBloc> {
  App({super.key}) : super(groups: {I18nGroups.locale});
  @override Widget onBuild(BuildContext c, StreamStatus s) =>
      MaterialApp(locale: bloc.state.locale, /* ... */);
}

// 3. Asset-backed source (assets/i18n/<tag>.json) + a language picker
//    I18nConfig(source: AssetJsonTranslationSource(['en','es']))
onTap: () => i18n.setLocale(const Locale('es'));   // persists the choice

// 4. Pluralization
Text(bloc.plural('cart.items', cartCount));   // 0→.other, 1→.one, n→.other; {count} filled
```

## Testing

Headless — `MapTranslationSource` + a fake persistence + injected system locale:

```dart
class FakePersistence implements LocalePersistence {
  LocaleChoice? saved;
  @override Future<LocaleChoice?> load() async => saved;
  @override Future<void> save(LocaleChoice c) async => saved = c;
}

final bloc = I18nBloc.withConfig(I18nConfig(
  source: MapTranslationSource({'en': {'hi': 'Hi {n}'}, 'es': {'hi': 'Hola {n}'}}),
  persistence: FakePersistence(),
  resolveSystemLocale: () => const Locale('es'),   // no binding needed
  followSystemByDefault: true,
));
await settle();
expect(bloc.state.locale, const Locale('es'));
expect(bloc.t('hi', args: {'n': 'Ada'}), 'Hola Ada');
bloc.setLocale(const Locale('en'));
await settle();
expect(bloc.t('hi', args: {'n': 'Ada'}), 'Hi Ada');
```

## Failure modes

- A missing key → `onMissing(key)` if set, else the **key itself** is returned
  (never throws). Unknown `{placeholder}` is left literal.
- `source.load` throwing → surfaces as a bloc failure; `isLoading` may remain set
  (the post-load emit didn't run) — sources should fail fast.
- `persistence.save` throwing on `setLocale` → the locale still switched
  in-memory; only persistence failed (surfaces as failure).
- Init does **not** persist (it's restoring/defaulting, not a user choice).

## Anti-patterns

- ❌ Using this for date/number/currency formatting — that's `intl`.
- ❌ Copying translation strings into `juice_storage` — only the locale *choice*
  is persisted; the `TranslationSource` is the single source of truth.
- ❌ Reading `bloc.t(...)` in a widget that isn't in the `i18n:translations`
  rebuild group — it won't re-translate on locale switch.
- ❌ Assuming `state.translations` holds all locales — it holds only the active one.

## Integrates with

- **juice_storage** — `StorageLocalePersistence(storageBloc)` (the default,
  substrate direct-dep). Mirrors pubspec's `juice_storage` dependency.

## Invariants

- Resolution order: exact (language+country) → language-only → `fallbackLocale`.
- Only the active locale's strings live in state; switching replaces them.
- `setLocale`/`useSystemLocale` persist; `InitializeI18nEvent` does not.

## See also

`SPEC.md` (design + storage model) · `README.md` (narrative) · repo `AGENTS.md`.
