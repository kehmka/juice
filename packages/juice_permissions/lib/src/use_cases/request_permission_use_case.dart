import 'package:juice/juice.dart';

import '../permissions_bloc.dart';
import '../permissions_events.dart';
import '../permissions_state.dart';
import 'permissions_emit_mixin.dart';

/// Handles [RequestPermissionEvent] — prompt the user. One prompt per
/// permission: the event is `singleflight` keyed by its permission, so a
/// request arriving while this one prompts joins it instead of running.
class RequestPermissionUseCase
    extends BlocUseCase<PermissionsBloc, RequestPermissionEvent>
    with PermissionsEmit<RequestPermissionEvent> {
  @override
  Future<void> execute(RequestPermissionEvent event) async {
    final p = event.permission;

    // Mark in-flight.
    emitUpdate(
      newState: bloc.state.copyWith(inFlight: {...bloc.state.inFlight, p}),
      groupsToRebuild: {PermissionsGroups.inFlight, PermissionsGroups.of(p)},
    );

    try {
      final status = await bloc.provider.request(p);
      emitStatuses(
        {p: status},
        inFlight: {...bloc.state.inFlight}..remove(p),
      );
      event.succeed(status);
    } catch (error, stackTrace) {
      emitFailure(
        newState: bloc.state.copyWith(
          inFlight: {...bloc.state.inFlight}..remove(p),
        ),
        groupsToRebuild: {PermissionsGroups.inFlight, PermissionsGroups.of(p)},
        error: error,
        errorStackTrace: stackTrace,
      );
      // The in-flight mark above was this event's first status, so an
      // awaiting caller is past it and waiting on the result.
      event.fail(error, stackTrace);
    }
  }
}
