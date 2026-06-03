import 'package:juice/juice.dart';

import '../connectivity_bloc.dart';
import '../connectivity_events.dart';
import '../connectivity_provider.dart';
import '../connectivity_state.dart';

/// Handles [ConnectivityChangedEvent].
///
/// Derives the online/offline [ConnectivityStatus] from the snapshot and emits
/// only when something actually changed, with precise rebuild groups.
class ConnectivityChangedUseCase
    extends BlocUseCase<ConnectivityBloc, ConnectivityChangedEvent> {
  @override
  Future<void> execute(ConnectivityChangedEvent event) async {
    final snapshot = event.snapshot;
    final status = _statusFor(snapshot);

    final statusChanged = status != bloc.state.status;
    final typeChanged = snapshot.type != bloc.state.connectionType;
    if (!statusChanged && !typeChanged) return; // no-op

    final groups = <String>{};
    if (statusChanged) groups.add(ConnectivityGroups.status);
    if (typeChanged) groups.add(ConnectivityGroups.type);

    emitUpdate(
      newState: bloc.state.copyWith(
        status: status,
        connectionType: snapshot.type,
        lastChangedAt: DateTime.now(),
      ),
      groupsToRebuild: groups,
    );
  }

  /// Offline when there is no interface, or when a reachability probe says the
  /// internet is unreachable; online otherwise.
  ConnectivityStatus _statusFor(ConnectivitySnapshot s) {
    if (s.type == ConnectionType.none) return ConnectivityStatus.offline;
    if (s.reachable == false) return ConnectivityStatus.offline;
    return ConnectivityStatus.online;
  }
}
