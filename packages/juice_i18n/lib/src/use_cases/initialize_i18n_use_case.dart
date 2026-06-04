import 'package:juice/juice.dart';

import '../i18n_bloc.dart';
import '../i18n_events.dart';
import 'i18n_load_mixin.dart';

/// Handles [InitializeI18nEvent] — configure, then load the initial locale:
/// the persisted choice if any, else system (when `followSystemByDefault`),
/// else the fallback.
class InitializeI18nUseCase extends BlocUseCase<I18nBloc, InitializeI18nEvent>
    with I18nLoad<InitializeI18nEvent> {
  @override
  Future<void> execute(InitializeI18nEvent event) async {
    bloc.configure(event.config);

    final saved = await bloc.persistence?.load();
    if (saved != null) {
      final target =
          saved.followSystem ? bloc.systemLocale() : saved.locale;
      await loadAndApply(target,
          followSystem: saved.followSystem, persist: false);
      return;
    }

    final followSystem = event.config.followSystemByDefault;
    final target =
        followSystem ? bloc.systemLocale() : event.config.fallbackLocale;
    await loadAndApply(target, followSystem: followSystem, persist: false);
  }
}
