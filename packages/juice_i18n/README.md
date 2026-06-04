# juice_i18n

Reactive locale selection and translation lookup as a
[Juice](https://pub.dev/packages/juice) bloc, behind swappable source and
persistence seams.

[![pub package](https://img.shields.io/pub/v/juice_i18n.svg)](https://pub.dev/packages/juice_i18n)
[![License: MIT](https://img.shields.io/badge/license-MIT-purple.svg)](LICENSE)

## What it owns

Two jobs: **which language** (active `Locale`, follow-system, resolution +
fallback, persistence) and **what the words are** (`t(key)` lookup +
interpolation + pluralization, strings from a pluggable source). Switching
locale reloads and rebuilds via groups.

It does **not** own date/number/currency **formatting** — that's `intl`. And it
complements Flutter's gen-l10n rather than replacing it (a custom source can
wrap your `AppLocalizations`).

## Install

```yaml
dependencies:
  juice_i18n: ^0.1.0
```

## Use

```dart
import 'package:juice/juice.dart';
import 'package:juice_i18n/juice_i18n.dart';

final i18n = I18nBloc.withConfig(I18nConfig(
  source: MapTranslationSource({
    'en': {'greeting': 'Hello {name}', 'cart.items.other': '{count} items'},
    'es': {'greeting': 'Hola {name}', 'cart.items.other': '{count} artículos'},
  }),
  persistence: StorageLocalePersistence(storageBloc),
));

class Greeting extends StatelessJuiceWidget<I18nBloc> {
  Greeting({super.key}) : super(groups: {I18nGroups.translations});

  @override
  Widget onBuild(BuildContext context, StreamStatus status) {
    return Column(children: [
      Text(bloc.t('greeting', args: {'name': 'Ada'})),
      Text(bloc.plural('cart.items', 3)), // "3 items"
    ]);
  }
}

// elsewhere: i18n.setLocale(const Locale('es'));  i18n.useSystemLocale();
```

Feed `i18n.state.locale` to `MaterialApp.locale` (and pass the standard
`localizationsDelegates` / `supportedLocales`).

## Sources

| Source | Use |
|--------|-----|
| `MapTranslationSource` | in-memory maps — tests, small apps |
| `AssetJsonTranslationSource` | `assets/i18n/<locale>.json` flat JSON |
| *custom* | implement `TranslationSource` for a backend or gen-l10n wrapper |

## What's stored where

- **Translation strings** come from the `TranslationSource` (in-code maps,
  bundled `assets/i18n/<locale>.json`, or your backend) and are **never copied
  into storage** — the source is their source of truth.
- Only the **current locale's** strings are in memory (`state.translations`);
  switching locale reloads and replaces them.
- Only the **locale choice** (tag + follow-system) is persisted, via
  `LocalePersistence` (SharedPreferences by default). On startup the bloc reads
  the saved choice, then loads that locale's strings from the source.

> **Upcoming:** a `StorageBloc`-backed caching `TranslationSource` (opt-in,
> wraps another source) for persisting a remote source's strings — offline use
> and faster startup, without changing the strings-out-of-storage base contract.

## Lookup

- `t('home.title', {args})` — interpolates `{placeholder}` from `args`.
- `plural('cart.items', count)` — selects `.zero`/`.one`/`.other`, interpolates `{count}`.
- Missing keys → `config.onMissing(key)` if set, else the key itself (UI never crashes on a missing string).

## Testability

Both seams mean the bloc runs headless: a `MapTranslationSource` + a fake
`LocalePersistence` (+ an injected `resolveSystemLocale`) cover locale switching,
resolution, lookup, and pluralization with no assets, storage, or binding.

## License

MIT License — see [LICENSE](LICENSE).
