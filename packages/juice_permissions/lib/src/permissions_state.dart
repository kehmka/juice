import 'package:juice/juice.dart';

import 'permission_provider.dart';

/// Rebuild groups emitted by [PermissionsBloc].
abstract final class PermissionsGroups {
  /// Any permission status changed.
  static const status = 'permissions:status';

  /// In-flight request set changed.
  static const inFlight = 'permissions:inflight';

  /// Group for a specific permission's status (e.g. `permissions:status:camera`).
  static String of(JuicePermission p) => 'permissions:status:${p.name}';
}

/// Immutable permissions state — a map of permission → status.
class PermissionsState extends BlocState {
  /// Known statuses. Absent permissions are [PermissionStatus.unknown].
  final Map<JuicePermission, PermissionStatus> statuses;

  /// Permissions with a request currently being prompted.
  final Set<JuicePermission> inFlight;

  const PermissionsState({
    this.statuses = const {},
    this.inFlight = const {},
  });

  static const initial = PermissionsState();

  /// Status of [p], or [PermissionStatus.unknown] if never read.
  PermissionStatus statusOf(JuicePermission p) =>
      statuses[p] ?? PermissionStatus.unknown;

  /// Strictly granted.
  bool isGranted(JuicePermission p) =>
      statusOf(p) == PermissionStatus.granted;

  /// Usable — granted, or partially/provisionally granted (iOS `limited` /
  /// `provisional`). Use this for "can I proceed?" checks.
  bool isUsable(JuicePermission p) {
    final s = statusOf(p);
    return s == PermissionStatus.granted ||
        s == PermissionStatus.limited ||
        s == PermissionStatus.provisional;
  }

  /// Whether [p] is permanently denied (must be changed in app settings).
  bool isPermanentlyDenied(JuicePermission p) =>
      statusOf(p) == PermissionStatus.permanentlyDenied;

  /// Whether a request for [p] is currently being prompted.
  bool isRequesting(JuicePermission p) => inFlight.contains(p);

  PermissionsState copyWith({
    Map<JuicePermission, PermissionStatus>? statuses,
    Set<JuicePermission>? inFlight,
  }) {
    return PermissionsState(
      statuses: statuses ?? this.statuses,
      inFlight: inFlight ?? this.inFlight,
    );
  }

  @override
  String toString() => 'PermissionsState(${statuses.length} known, '
      '${inFlight.length} in-flight)';
}
