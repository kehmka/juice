/// Reactive locale selection and translation lookup as a Juice bloc.
///
/// `I18nBloc` owns the active [Locale] and the loaded translations, sourced
/// through a swappable [TranslationSource] and remembered via a
/// [LocalePersistence] seam. It owns *which language* and *what the words are*;
/// it does not own date/number formatting (use `intl`).
///
/// ```dart
/// final i18n = I18nBloc.withConfig(I18nConfig(
///   source: MapTranslationSource({
///     'en': {'greeting': 'Hello {name}', 'cart.items.other': '{count} items'},
///     'es': {'greeting': 'Hola {name}', 'cart.items.other': '{count} artículos'},
///   }),
/// ));
///
/// class Greeting extends StatelessJuiceWidget<I18nBloc> {
///   Greeting({super.key}) : super(groups: {I18nGroups.translations});
///   @override
///   Widget onBuild(BuildContext context, StreamStatus status) =>
///       Text(bloc.t('greeting', args: {'name': 'Ada'}));
/// }
/// ```
library juice_i18n;

export 'src/i18n_bloc.dart';
export 'src/i18n_config.dart';
export 'src/i18n_events.dart';
export 'src/i18n_state.dart';
export 'src/locale_persistence.dart';
export 'src/providers/asset_json_translation_source.dart';
export 'src/providers/map_translation_source.dart';
export 'src/providers/storage_locale_persistence.dart';
export 'src/translation_source.dart';
