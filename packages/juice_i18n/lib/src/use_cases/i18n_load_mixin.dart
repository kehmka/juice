import 'package:juice/juice.dart';

import '../i18n_bloc.dart';
import '../i18n_state.dart';
import '../locale_persistence.dart';

/// Shared "resolve → load → emit → persist" flow for i18n use cases.
mixin I18nLoad<E extends EventBase> on BlocUseCase<I18nBloc, E> {
  /// Resolve [target] against supported locales, load its translations, emit,
  /// and (optionally) persist the choice.
  Future<void> loadAndApply(
    Locale target, {
    required bool followSystem,
    bool persist = true,
  }) async {
    final resolved = bloc.resolveLocale(target);

    emitUpdate(
      newState: bloc.state.copyWith(isLoading: true),
      groupsToRebuild: {I18nGroups.translations},
    );

    final translations = await bloc.source.load(resolved);

    emitUpdate(
      newState: bloc.state.copyWith(
        locale: resolved,
        followSystem: followSystem,
        translations: translations,
        isLoading: false,
        supportedLocales: bloc.source.supportedLocales,
      ),
      groupsToRebuild: I18nGroups.all,
    );

    if (persist) {
      await bloc.persistence?.save(
        LocaleChoice(locale: resolved, followSystem: followSystem),
      );
    }
  }
}
