import 'package:juice/juice.dart';

import '../routing_bloc.dart';
import '../routing_events.dart';
import '../routing_state.dart';
import '../routing_types.dart';

/// Use case for popping all routes except the root.
///
/// Bypasses guards. Clears the stack down to the first entry.
class PopToRootUseCase extends BlocUseCase<RoutingBloc, PopToRootEvent> {
  @override
  Future<void> execute(PopToRootEvent event) async {
    final state = bloc.state;

    // Check if already at root
    if (state.stack.length <= 1) {
      return;
    }

    final now = DateTime.now();

    // Collect popped entries for history
    final poppedEntries = state.stack.sublist(1);
    var newHistory = List<HistoryEntry>.from(state.history);

    for (final entry in poppedEntries.reversed) {
      final timeOnRoute = now.difference(entry.pushedAt);
      newHistory.add(HistoryEntry(
        path: entry.path,
        timestamp: now,
        type: NavigationType.pop,
        timeOnRoute: timeOnRoute,
      ));
    }

    // Keep only root
    final newStack = [state.stack.first];

    // Trim history if needed
    final maxHistory = bloc.config.maxHistorySize;
    if (newHistory.length > maxHistory) {
      newHistory = newHistory.sublist(newHistory.length - maxHistory);
    }

    emitUpdate(
      newState: state.copyWith(
        stack: newStack,
        history: newHistory,
        clearError: true,
      ),
      groupsToRebuild: {
        RoutingGroups.stack,
        RoutingGroups.current,
        RoutingGroups.history,
      },
    );

    log('Popped ${poppedEntries.length} routes to root');
  }
}
