# juice_i18n Specification

> **Status:** Implemented (shipping).
> **Package:** `juice_i18n`
> **Primary Bloc:** `I18nBloc`

## Overview

`juice_i18n` is a **presentation-tier** bloc owning two jobs: *which language*
(locale selection) and *what the words are* (translation lookup). It is reactive
— switching locale reloads strings and rebuilds via groups.

## Domain boundary

- **Owns:** active `Locale`, follow-system, supported-locale resolution +
  fallback, locale persistence, and `t()`/`plural()` lookup with interpolation.
- **Does NOT own:** date/number/currency **formatting** (use `intl`). Does not
  replace gen-l10n — complements it (a custom source can wrap `AppLocalizations`).

## Dependencies

| Package | Why |
|---------|-----|
| `juice` | core bloc infrastructure |
| `juice_storage` | default `LocalePersistence` — substrate, direct-dep OK |

Notably **not `intl`** — formatting is out of scope.

## Seams (two)

```dart
abstract class TranslationSource {        // where strings come from
  List<Locale> get supportedLocales;
  Future<Map<String, String>> load(Locale locale);
  Future<void> dispose();
}
abstract class LocalePersistence {        // remember the choice
  Future<LocaleChoice?> load();
  Future<void> save(LocaleChoice choice);
}
```

Defaults: `MapTranslationSource`, `AssetJsonTranslationSource`;
`StorageLocalePersistence`. The platform locale is read via an injectable
`resolveSystemLocale` callback (defaults to `PlatformDispatcher`), keeping the
bloc testable without a binding.

## Storage model — what lives where

Two distinct things, deliberately kept separate:

| Thing | Where it lives | Persisted? |
|-------|----------------|------------|
| **Translation strings** | the `TranslationSource` — in-code maps (`MapTranslationSource`), bundled assets `assets/i18n/<tag>.json` (`AssetJsonTranslationSource`), or a custom backend | **No.** Reloaded from the source each session. |
| **Current locale's strings** | `I18nState.translations` (in memory) | No — only the *active* locale is held; switching locale replaces it. |
| **The locale choice** (tag + follow-system) | `LocalePersistence` → SharedPreferences keys `juice_i18n_locale` / `juice_i18n_follow_system` (`StorageLocalePersistence`) | **Yes** (if persistence is configured). |

The strings are **never copied into storage** — the source is their single
source of truth. On startup the bloc reads the saved *choice* from prefs, then
asks the `TranslationSource` to load that locale's strings.

**Upcoming:** a `StorageBloc`-backed caching `TranslationSource` decorator that
persists a remote source's strings (for offline use and faster startup) — opt-in,
wrapping another source. The base contract still keeps strings out of storage;
caching is a deliberate, separate layer.

## State

```dart
class I18nState extends BlocState {
  final Locale locale;                 // → MaterialApp.locale
  final bool followSystem;
  final List<Locale> supportedLocales;
  final Map<String, String> translations;  // current locale
  final bool isLoading;
  static const initial = I18nState();
}
```

## Lookup

- `t(key, {args})` — `translations[key]` (→ `onMissing(key)` → key), then
  interpolates `{placeholder}` from `args`.
- `plural(key, count, {args})` — selects `key.zero`/`key.one`/`key.other` by
  count (→ `key.other` → `key`), interpolates `{count}`.

Resolution: exact (language+country) → language-only → `fallbackLocale`.

## Events

| Event | Effect | Groups |
|-------|--------|--------|
| `InitializeI18nEvent(config)` | configure, load initial locale (persisted → system → fallback) | `i18n:locale`, `i18n:translations` |
| `SetLocaleEvent(locale)` | resolve + load + persist (followSystem=false) | both |
| `UseSystemLocaleEvent` | resolve system + load + persist (followSystem=true) | both |

All three share the `I18nLoad` mixin (resolve → load → emit → persist).

## Testing

`I18nBloc` runs headless via `MapTranslationSource` + a fake `LocalePersistence`
+ an injected `resolveSystemLocale`: init/fallback/system/restore, locale
switching, resolution-to-fallback, missing-key, and pluralization (incl.
fallback to `.other`).

## Spec Version

| Version | Date | Status |
|---------|------|--------|
| 1.0 | 2026-05-28 | Implemented |
