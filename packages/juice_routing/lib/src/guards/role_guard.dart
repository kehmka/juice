import '../route_context.dart';
import '../route_guard.dart';

/// Built-in guard that blocks users who lack a required role.
///
/// Uses a callback to check the user's role, so it's decoupled from
/// any specific auth/role implementation.
///
/// Example:
/// ```dart
/// RoleGuard(
///   hasRole: () => userBloc.state.roles.contains('admin'),
///   roleName: 'admin',
/// )
/// ```
///
/// When the user does not have the required role, navigation is blocked
/// with a descriptive reason message.
class RoleGuard extends RouteGuard {
  /// Callback that returns `true` when the user has the required role.
  final bool Function() hasRole;

  /// Human-readable name of the required role (used in block reason).
  final String roleName;

  const RoleGuard({
    required this.hasRole,
    required this.roleName,
  });

  @override
  String get name => 'RoleGuard($roleName)';

  @override
  Future<GuardResult> check(RouteContext context) async {
    if (hasRole()) {
      return const GuardResult.allow();
    }
    return GuardResult.block(reason: 'Requires role: $roleName');
  }
}
