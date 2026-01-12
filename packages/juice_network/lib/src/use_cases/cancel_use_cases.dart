import 'package:juice/juice.dart';

import '../fetch_bloc.dart';
import '../fetch_events.dart';
import '../fetch_state.dart';

/// Use case to cancel a specific request.
class CancelRequestUseCase extends BlocUseCase<FetchBloc, CancelRequestEvent> {
  @override
  Future<void> execute(CancelRequestEvent event) async {
    final key = event.key;
    final canonical = key.canonical;

    // Get the request status
    final status = bloc.state.activeRequests[canonical];
    if (status == null) return; // Already completed or not found

    // Cancel the request
    status.cancelToken?.cancel(event.reason ?? 'Cancelled');

    // Update state
    final newRequests = {...bloc.state.activeRequests}..remove(canonical);

    emitUpdate(
      groupsToRebuild: {
        FetchGroups.inflight,
        FetchGroups.request(canonical),
      },
      newState: bloc.state.copyWith(
        activeRequests: newRequests,
        inflightCount: bloc.state.inflightCount - 1,
      ),
    );
  }
}

/// Use case to cancel all requests in a scope.
class CancelScopeUseCase extends BlocUseCase<FetchBloc, CancelScopeEvent> {
  @override
  Future<void> execute(CancelScopeEvent event) async {
    final scope = event.scope;
    final toCancel = <String>[];

    // Find all requests in this scope
    for (final entry in bloc.state.activeRequests.entries) {
      if (entry.value.scope == scope) {
        entry.value.cancelToken?.cancel(event.reason ?? 'Scope cancelled');
        toCancel.add(entry.key);
      }
    }

    if (toCancel.isEmpty) return;

    // Update state
    final newRequests = {...bloc.state.activeRequests};
    for (final key in toCancel) {
      newRequests.remove(key);
    }

    // Build groups to rebuild
    final groups = <String>{FetchGroups.inflight};
    for (final key in toCancel) {
      groups.add(FetchGroups.request(key));
    }

    emitUpdate(
      groupsToRebuild: groups,
      newState: bloc.state.copyWith(
        activeRequests: newRequests,
        inflightCount: bloc.state.inflightCount - toCancel.length,
      ),
    );
  }
}

/// Use case to cancel all inflight requests.
class CancelAllUseCase extends BlocUseCase<FetchBloc, CancelAllEvent> {
  @override
  Future<void> execute(CancelAllEvent event) async {
    if (bloc.state.activeRequests.isEmpty) return;

    // Cancel all requests
    for (final status in bloc.state.activeRequests.values) {
      status.cancelToken?.cancel(event.reason ?? 'All cancelled');
    }

    // Clear coalescer
    bloc.coalescer.clear();

    emitUpdate(
      groupsToRebuild: {FetchGroups.inflight},
      newState: bloc.state.copyWith(
        activeRequests: {},
        inflightCount: 0,
      ),
    );
  }
}
