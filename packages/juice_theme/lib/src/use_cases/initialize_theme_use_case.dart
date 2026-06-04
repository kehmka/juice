import 'package:juice/juice.dart';

import '../theme_bloc.dart';
import '../theme_events.dart';
import '../theme_state.dart';

/// Handles [InitializeThemeEvent] — configure persistence and load the saved
/// selection (falling back to the config defaults).
class InitializeThemeUseCase
    extends BlocUseCase<ThemeBloc, InitializeThemeEvent> {
  @override
  Future<void> execute(InitializeThemeEvent event) async {
    bloc.configure(event.config);

    final saved = await bloc.persistence?.load();
    emitUpdate(
      newState: ThemeState(
        mode: saved?.mode ?? event.config.defaultMode,
        flavor: saved?.flavor ?? event.config.defaultFlavor,
      ),
      groupsToRebuild: ThemeGroups.all,
    );
  }
}
