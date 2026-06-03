import 'package:juice/juice.dart';
import 'package:juice_permissions/juice_permissions.dart';

/// A self-contained [PermissionProvider] for the demo — no real OS prompts.
///
/// Implementing [PermissionProvider] is the framework's intended seam. This one
/// simulates a user response: the first request on a permission grants it, a
/// permission listed in [denyPermanently] becomes permanently denied instead.
class DemoPermissionProvider implements PermissionProvider {
  final Set<JuicePermission> denyPermanently;
  final Map<JuicePermission, PermissionStatus> _statuses = {};

  DemoPermissionProvider({this.denyPermanently = const {}});

  @override
  Future<PermissionStatus> status(JuicePermission p) async =>
      _statuses[p] ?? PermissionStatus.denied;

  @override
  Future<PermissionStatus> request(JuicePermission p) async {
    await Future<void>.delayed(const Duration(milliseconds: 400));
    final result = denyPermanently.contains(p)
        ? PermissionStatus.permanentlyDenied
        : PermissionStatus.granted;
    _statuses[p] = result;
    return result;
  }

  @override
  Future<Map<JuicePermission, PermissionStatus>> requestAll(
          Set<JuicePermission> ps) async =>
      {for (final p in ps) p: await request(p)};

  @override
  Future<bool> openSettings() async => true;

  @override
  Future<void> dispose() async {}
}
