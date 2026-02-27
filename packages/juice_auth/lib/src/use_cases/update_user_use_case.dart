import 'package:juice/juice.dart';

import '../auth_bloc.dart';
import '../auth_events.dart';
import '../auth_state.dart';

/// Handles [UpdateUserEvent] — updates user profile in state.
class UpdateUserUseCase extends BlocUseCase<AuthBloc, UpdateUserEvent> {
  @override
  Future<void> execute(UpdateUserEvent event) async {
    if (!bloc.state.isAuthenticated) {
      log('Ignoring user update — not authenticated', level: Level.warning);
      return;
    }

    emitUpdate(
      newState: bloc.state.copyWith(user: event.updatedUser),
      groupsToRebuild: {AuthGroups.user},
    );

    log('User profile updated: ${event.updatedUser.id}');
  }
}
