import 'package:juice/juice.dart';

import '../permission_provider.dart';
import '../permissions_bloc.dart';
import '../permissions_events.dart';
import '../permissions_state.dart';
import 'permissions_emit_mixin.dart';

/// Handles [RequestPermissionEvent] — prompt the user, with per-permission
/// singleflight so concurrent requests collapse to a single OS prompt.
class RequestPermissionUseCase
    extends BlocUseCase<PermissionsBloc, RequestPermissionEvent>
    with PermissionsEmit<RequestPermissionEvent> {
  @override
  Future<void> execute(RequestPermissionEvent event) async {
    final p = event.permission;

    // Singleflight: a request for p is already prompting — join it.
    final existing = bloc.requestsInFlight[p];
    if (existing != null) {
      try {
        await existing.future;
      } catch (_) {
        // Surfaced by the first caller.
      }
      return;
    }

    final completer = Completer<PermissionStatus>();
    bloc.requestsInFlight[p] = completer;
    completer.future.ignore();

    // Mark in-flight.
    emitUpdate(
      newState: bloc.state.copyWith(inFlight: {...bloc.state.inFlight, p}),
      groupsToRebuild: {PermissionsGroups.inFlight, PermissionsGroups.of(p)},
    );

    try {
      final status = await bloc.provider.request(p);
      completer.complete(status);
      emitStatuses(
        {p: status},
        inFlight: {...bloc.state.inFlight}..remove(p),
      );
    } catch (error, stackTrace) {
      if (!completer.isCompleted) completer.completeError(error);
      emitFailure(
        newState: bloc.state.copyWith(
          inFlight: {...bloc.state.inFlight}..remove(p),
        ),
        groupsToRebuild: {PermissionsGroups.inFlight, PermissionsGroups.of(p)},
        error: error,
        errorStackTrace: stackTrace,
      );
    } finally {
      bloc.requestsInFlight.remove(p);
    }
  }
}
