import 'package:juice/juice.dart';

import '../permission_provider.dart';
import '../permissions_bloc.dart';
import '../permissions_events.dart';
import 'permissions_emit_mixin.dart';

/// Handles [InitializePermissionsEvent] — store config and pre-read statuses.
class InitializePermissionsUseCase
    extends BlocUseCase<PermissionsBloc, InitializePermissionsEvent>
    with PermissionsEmit<InitializePermissionsEvent> {
  @override
  Future<void> execute(InitializePermissionsEvent event) async {
    bloc.configure(event.config);
    if (event.config.precheck.isEmpty) return;

    final updates = <JuicePermission, PermissionStatus>{};
    for (final p in event.config.precheck) {
      updates[p] = await bloc.provider.status(p);
    }
    emitStatuses(updates);
  }
}
