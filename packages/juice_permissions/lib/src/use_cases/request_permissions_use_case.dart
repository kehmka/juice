import 'package:juice/juice.dart';

import '../permissions_bloc.dart';
import '../permissions_events.dart';
import '../permissions_state.dart';
import 'permissions_emit_mixin.dart';

/// Handles [RequestPermissionsEvent] — prompt for several permissions in one
/// OS call. (No singleflight on the batch; use single requests for that.)
class RequestPermissionsUseCase
    extends BlocUseCase<PermissionsBloc, RequestPermissionsEvent>
    with PermissionsEmit<RequestPermissionsEvent> {
  @override
  Future<void> execute(RequestPermissionsEvent event) async {
    final ps = event.permissions;
    if (ps.isEmpty) return;

    emitUpdate(
      newState: bloc.state.copyWith(inFlight: {...bloc.state.inFlight, ...ps}),
      groupsToRebuild: {
        PermissionsGroups.inFlight,
        ...ps.map(PermissionsGroups.of),
      },
    );

    try {
      final results = await bloc.provider.requestAll(ps);
      emitStatuses(
        results,
        inFlight: {...bloc.state.inFlight}..removeAll(ps),
      );
    } catch (error, stackTrace) {
      emitFailure(
        newState: bloc.state.copyWith(
          inFlight: {...bloc.state.inFlight}..removeAll(ps),
        ),
        groupsToRebuild: {
          PermissionsGroups.inFlight,
          ...ps.map(PermissionsGroups.of),
        },
        error: error,
        errorStackTrace: stackTrace,
      );
    }
  }
}
