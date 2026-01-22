import 'package:juice/juice.dart';

import '../routing_bloc.dart';
import '../routing_errors.dart';
import '../routing_events.dart';
import '../routing_state.dart';
import '../routing_types.dart';

/// Use case for popping the current route.
///
/// Bypasses guards and executes immediately.
/// Fails with [CannotPopError] if at root (single entry on stack).
class PopUseCase extends BlocUseCase<RoutingBloc, PopEvent> {
  @override
  Future<void> execute(PopEvent event) async {
    final state = bloc.state;

    // Check if we can pop
    if (!state.canPop) {
      emitFailure(
        newState: state.copyWith(
          error: CannotPopError(),
        ),
        groupsToRebuild: {RoutingGroups.error},
      );
      return;
    }

    final now = DateTime.now();
    final poppedEntry = state.stack.last;

    // Calculate time on route
    final timeOnRoute = now.difference(poppedEntry.pushedAt);

    // Create history entry for the pop
    final historyEntry = HistoryEntry(
      path: poppedEntry.path,
      timestamp: now,
      type: NavigationType.pop,
      timeOnRoute: timeOnRoute,
    );

    // Update stack
    final newStack = state.stack.sublist(0, state.stack.length - 1);

    emitUpdate(
      newState: state.copyWith(
        stack: newStack,
        history: [...state.history, historyEntry],
        clearError: true,
      ),
      groupsToRebuild: {
        RoutingGroups.stack,
        RoutingGroups.current,
        RoutingGroups.history,
      },
    );

    log('Popped ${poppedEntry.path}, time on route: $timeOnRoute');
  }
}
