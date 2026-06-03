/// Runtime permission grant-state as a Juice bloc.
///
/// `PermissionsBloc` owns the grant-state machine for each [JuicePermission],
/// sourced through a swappable [PermissionProvider] seam (default:
/// `PermissionHandlerProvider`). Because the bloc depends on the provider
/// interface rather than a platform plugin, it is fully testable without a
/// device.
///
/// ```dart
/// final permissions = PermissionsBloc.withConfig(PermissionsConfig());
///
/// class CameraGate extends StatelessJuiceWidget<PermissionsBloc> {
///   CameraGate({super.key})
///       : super(groups: {PermissionsGroups.of(JuicePermission.camera)});
///   @override
///   Widget onBuild(BuildContext context, StreamStatus status) {
///     final ok = bloc.state.isUsable(JuicePermission.camera);
///     return ok ? const CameraView() : RequestButton();
///   }
/// }
/// ```
library juice_permissions;

export 'src/permission_provider.dart';
export 'src/permissions_bloc.dart';
export 'src/permissions_config.dart';
export 'src/permissions_events.dart';
export 'src/permissions_state.dart';
export 'src/providers/permission_handler_provider.dart';
