import 'package:juice/juice.dart';

import '../permission_provider.dart';
import '../permissions_bloc.dart';
import '../permissions_state.dart';

/// Shared emit helpers for permission use cases — one place that maps status
/// updates to the right rebuild groups.
mixin PermissionsEmit<E extends EventBase>
    on BlocUseCase<PermissionsBloc, E> {
  /// Merge [updates] into state and emit, optionally replacing the in-flight
  /// set. Fires `permissions:status` + per-permission groups for changed
  /// statuses, and `permissions:inflight` when [inFlight] is provided.
  void emitStatuses(
    Map<JuicePermission, PermissionStatus> updates, {
    Set<JuicePermission>? inFlight,
  }) {
    final groups = <String>{};
    if (updates.isNotEmpty) {
      groups.add(PermissionsGroups.status);
      for (final p in updates.keys) {
        groups.add(PermissionsGroups.of(p));
      }
    }
    if (inFlight != null) groups.add(PermissionsGroups.inFlight);

    emitUpdate(
      newState: bloc.state.copyWith(
        statuses:
            updates.isEmpty ? null : {...bloc.state.statuses, ...updates},
        inFlight: inFlight,
      ),
      groupsToRebuild: groups,
    );
  }
}
