import 'package:juice/juice.dart';

import '../theme_bloc.dart';
import '../theme_events.dart';
import '../theme_state.dart';
import 'theme_emit_mixin.dart';

/// Handles [SetFlavorEvent] — set or clear the named flavor.
class SetFlavorUseCase extends BlocUseCase<ThemeBloc, SetFlavorEvent>
    with ThemeEmit<SetFlavorEvent> {
  @override
  Future<void> execute(SetFlavorEvent event) async {
    if (event.flavor == bloc.state.flavor) return;
    await commit(
      bloc.state.copyWith(flavor: event.flavor, clearFlavor: event.flavor == null),
      {ThemeGroups.flavor},
    );
  }
}
