import 'package:juice/juice.dart';

/// Rebuild groups emitted by [I18nBloc].
abstract final class I18nGroups {
  /// Active locale changed.
  static const locale = 'i18n:locale';

  /// Loaded translations changed (e.g. after a locale switch).
  static const translations = 'i18n:translations';

  static const all = {locale, translations};
}

/// Immutable i18n state.
class I18nState extends BlocState {
  /// The active locale.
  final Locale locale;

  /// Whether the locale follows the platform.
  final bool followSystem;

  /// Locales the source can serve.
  final List<Locale> supportedLocales;

  /// Flat key→string map for the active locale.
  final Map<String, String> translations;

  /// Whether a locale's translations are currently loading.
  final bool isLoading;

  const I18nState({
    this.locale = const Locale('en'),
    this.followSystem = false,
    this.supportedLocales = const [],
    this.translations = const {},
    this.isLoading = false,
  });

  static const initial = I18nState();

  I18nState copyWith({
    Locale? locale,
    bool? followSystem,
    List<Locale>? supportedLocales,
    Map<String, String>? translations,
    bool? isLoading,
  }) {
    return I18nState(
      locale: locale ?? this.locale,
      followSystem: followSystem ?? this.followSystem,
      supportedLocales: supportedLocales ?? this.supportedLocales,
      translations: translations ?? this.translations,
      isLoading: isLoading ?? this.isLoading,
    );
  }

  @override
  String toString() =>
      'I18nState($locale, followSystem: $followSystem, ${translations.length} keys)';
}
