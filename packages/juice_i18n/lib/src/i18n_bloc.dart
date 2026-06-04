import 'dart:ui' show PlatformDispatcher;

import 'package:juice/juice.dart';

import 'i18n_config.dart';
import 'i18n_events.dart';
import 'i18n_state.dart';
import 'locale_persistence.dart';
import 'translation_source.dart';
import 'use_cases/initialize_i18n_use_case.dart';
import 'use_cases/set_locale_use_case.dart';
import 'use_cases/use_system_locale_use_case.dart';

/// Bloc that owns locale selection and translation lookup.
///
/// Reads strings through a [TranslationSource] and remembers the choice through
/// a [LocalePersistence] — both seams, so it's testable without assets or real
/// storage. Feed `bloc.state.locale` to `MaterialApp.locale`.
///
/// ```dart
/// final i18n = I18nBloc.withConfig(I18nConfig(
///   source: MapTranslationSource({'en': {'hi': 'Hi {name}'}, 'es': {'hi': 'Hola {name}'}}),
///   persistence: StorageLocalePersistence(storageBloc),
/// ));
/// // ... bloc.t('hi', args: {'name': 'Ada'})
/// ```
class I18nBloc extends JuiceBloc<I18nState> {
  late I18nConfig _config;

  I18nBloc()
      : super(
          I18nState.initial,
          [
            () => UseCaseBuilder(
                  typeOfEvent: InitializeI18nEvent,
                  useCaseGenerator: () => InitializeI18nUseCase(),
                ),
            () => UseCaseBuilder(
                  typeOfEvent: SetLocaleEvent,
                  useCaseGenerator: () => SetLocaleUseCase(),
                ),
            () => UseCaseBuilder(
                  typeOfEvent: UseSystemLocaleEvent,
                  useCaseGenerator: () => UseSystemLocaleUseCase(),
                ),
          ],
        );

  /// Create and initialize in one step.
  factory I18nBloc.withConfig(I18nConfig config) {
    final bloc = I18nBloc();
    bloc.send(InitializeI18nEvent(config: config));
    return bloc;
  }

  /// Store config during initialization.
  void configure(I18nConfig config) => _config = config;

  /// The translation source. Valid after initialization.
  TranslationSource get source => _config.source;

  /// The persistence seam (null = none).
  LocalePersistence? get persistence => _config.persistence;

  /// The platform locale (injectable for tests).
  Locale systemLocale() =>
      _config.resolveSystemLocale?.call() ?? PlatformDispatcher.instance.locale;

  /// Resolve [want] against the source's supported locales: exact (language +
  /// country) → language-only → fallback.
  Locale resolveLocale(Locale want) {
    final supported = source.supportedLocales;
    if (supported.isEmpty) return want;
    for (final l in supported) {
      if (l.languageCode == want.languageCode &&
          l.countryCode == want.countryCode) {
        return l;
      }
    }
    for (final l in supported) {
      if (l.languageCode == want.languageCode) return l;
    }
    return _config.fallbackLocale;
  }

  // === Lookup ===

  /// Translate [key] for the current locale, interpolating `{placeholder}`
  /// values from [args]. Missing keys fall back via `config.onMissing`, else
  /// the key itself.
  String t(String key, {Map<String, Object>? args}) {
    final raw =
        state.translations[key] ?? _config.onMissing?.call(key) ?? key;
    return _interpolate(raw, args);
  }

  /// Pluralized lookup: selects `key.zero` / `key.one` / `key.other` by [count]
  /// (falling back to `key.other`, then `key`), and interpolates `{count}`.
  String plural(String key, int count, {Map<String, Object>? args}) {
    final candidates = switch (count) {
      0 => ['$key.zero', '$key.other'],
      1 => ['$key.one', '$key.other'],
      _ => ['$key.other'],
    };
    final chosen = candidates.firstWhere(
      state.translations.containsKey,
      orElse: () => key,
    );
    final raw =
        state.translations[chosen] ?? _config.onMissing?.call(chosen) ?? chosen;
    return _interpolate(raw, {'count': count, ...?args});
  }

  String _interpolate(String template, Map<String, Object>? args) {
    if (args == null || args.isEmpty) return template;
    return template.replaceAllMapped(RegExp(r'\{(\w+)\}'), (m) {
      final name = m.group(1)!;
      return args.containsKey(name) ? '${args[name]}' : m.group(0)!;
    });
  }

  // === Convenience ===

  /// Switch to an explicit locale.
  void setLocale(Locale locale) => send(SetLocaleEvent(locale));

  /// Follow the platform locale.
  void useSystemLocale() => send(UseSystemLocaleEvent());

  @override
  Future<void> close() async {
    try {
      await _config.source.dispose();
    } catch (_) {
      // Source may never have been configured; ignore.
    }
    await super.close();
  }
}
