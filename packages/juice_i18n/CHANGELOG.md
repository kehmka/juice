# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.0] - 2026-05-28

### Added

- Initial release.
- **`I18nBloc`** — reactive locale selection + translation lookup; feed
  `state.locale` to `MaterialApp.locale`.
- **`t(key, {args})`** with `{placeholder}` interpolation, and **`plural(key, count)`**
  selecting `key.zero`/`key.one`/`key.other`.
- **`TranslationSource`** seam — `MapTranslationSource` (in-memory) and
  `AssetJsonTranslationSource` (`assets/i18n/<locale>.json`) defaults.
- **`LocalePersistence`** seam — `StorageLocalePersistence` default (remembers
  locale + follow-system).
- Locale resolution (exact → language → fallback), follow-system, and a
  configurable `onMissing` hook (returns the key by default).
- **Rebuild groups** — `i18n:locale`, `i18n:translations`.

### Out of scope

- Date/number/currency formatting — use `intl`. This package routes *words*.
