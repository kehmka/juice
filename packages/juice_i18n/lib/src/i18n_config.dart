import 'package:flutter/widgets.dart' show Locale;

import 'locale_persistence.dart';
import 'translation_source.dart';

/// Configuration for [I18nBloc].
class I18nConfig {
  /// Where translation strings come from.
  final TranslationSource source;

  /// Locale used when nothing else resolves.
  final Locale fallbackLocale;

  /// Where the chosen locale is remembered. `null` = no persistence.
  final LocalePersistence? persistence;

  /// On first run with no saved choice, follow the platform locale.
  final bool followSystemByDefault;

  /// Resolves the platform locale. Defaults to `PlatformDispatcher`; inject a
  /// fixed value in tests.
  final Locale Function()? resolveSystemLocale;

  /// Called when a key has no translation. Return a fallback string; default
  /// behavior (when null) is to return the key itself.
  final String Function(String key)? onMissing;

  const I18nConfig({
    required this.source,
    this.fallbackLocale = const Locale('en'),
    this.persistence,
    this.followSystemByDefault = true,
    this.resolveSystemLocale,
    this.onMissing,
  });
}
