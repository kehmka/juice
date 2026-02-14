import 'package:juice/juice.dart';

import '../routing_bloc.dart';
import '../routing_events.dart';
import '../routing_state.dart';
import '../routing_types.dart';

/// Use case for popping routes until a condition is met.
///
/// Bypasses guards. Pops entries from the stack until [predicate] returns true.
/// The entry where predicate returns true remains on the stack.
class PopUntilUseCase extends BlocUseCase<RoutingBloc, PopUntilEvent> {
  @override
  Future<void> execute(PopUntilEvent event) async {
    final state = bloc.state;
    final now = DateTime.now();

    // Find where to stop
    var stopIndex = -1;
    for (var i = state.stack.length - 1; i >= 0; i--) {
      if (event.predicate(state.stack[i])) {
        stopIndex = i;
        break;
      }
    }

    // If no match found, keep root
    if (stopIndex == -1) {
      stopIndex = 0;
    }

    // Check if anything needs to be popped
    if (stopIndex == state.stack.length - 1) {
      // Already at matching entry
      return;
    }

    // Collect popped entries for history
    final poppedEntries = state.stack.sublist(stopIndex + 1);
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

    // Update stack
    final newStack = state.stack.sublist(0, stopIndex + 1);

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

    log('Popped ${poppedEntries.length} routes');
  }
}
