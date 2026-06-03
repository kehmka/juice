import 'package:juice/juice.dart';
import 'package:juice_permissions/juice_permissions.dart';

/// Lists a few permissions with live status + request buttons, bound to
/// [PermissionsBloc] via rebuild groups.
class HomeScreen extends StatelessJuiceWidget<PermissionsBloc> {
  HomeScreen({super.key}) : super(groups: {PermissionsGroups.status});

  static const _shown = [
    JuicePermission.camera,
    JuicePermission.microphone,
    JuicePermission.locationWhenInUse,
    JuicePermission.notification,
  ];

  @override
  Widget onBuild(BuildContext context, StreamStatus status) {
    return Scaffold(
      appBar: AppBar(title: const Text('juice_permissions demo')),
      body: ListView(
        children: [
          for (final p in _shown) _PermissionTile(p),
        ],
      ),
    );
  }
}

/// One row, bound to its own permission's rebuild group.
class _PermissionTile extends StatelessJuiceWidget<PermissionsBloc> {
  final JuicePermission permission;

  _PermissionTile(this.permission)
      : super(groups: {
          PermissionsGroups.of(permission),
          PermissionsGroups.inFlight,
        });

  @override
  Widget onBuild(BuildContext context, StreamStatus status) {
    final state = bloc.state;
    final requesting = state.isRequesting(permission);

    return ListTile(
      title: Text(permission.name),
      subtitle: Text(state.statusOf(permission).name),
      trailing: requesting
          ? const SizedBox(
              width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
          : state.isPermanentlyDenied(permission)
              ? TextButton(
                  onPressed: bloc.openAppSettings,
                  child: const Text('Settings'),
                )
              : FilledButton(
                  onPressed: () => bloc.request(permission),
                  child: Text(state.isUsable(permission) ? 'Granted' : 'Allow'),
                ),
    );
  }
}
