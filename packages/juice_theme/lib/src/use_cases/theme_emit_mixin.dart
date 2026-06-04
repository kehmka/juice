import 'package:juice/juice.dart';

import '../theme_bloc.dart';
import '../theme_persistence.dart';
import '../theme_state.dart';

/// Shared "emit then persist" helper for theme use cases — one place that keeps
/// state and persistence in sync.
mixin ThemeEmit<E extends EventBase> on BlocUseCase<ThemeBloc, E> {
  /// Emit [newState] under [groups], then persist the selection (if configured).
  Future<void> commit(ThemeState newState, Set<String> groups) async {
    emitUpdate(newState: newState, groupsToRebuild: groups);
    await bloc.persistence?.save(
      ThemeSelection(mode: newState.mode, flavor: newState.flavor),
    );
  }
}
