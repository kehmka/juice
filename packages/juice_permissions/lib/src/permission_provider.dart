/// A runtime permission, vendor-agnostic.
///
/// Mapped to the underlying platform permission by the [PermissionProvider]
/// (the default maps to `permission_handler`). Values not applicable to the
/// running platform report [PermissionStatus.granted] (nothing to ask).
enum JuicePermission {
  // Capture
  camera,
  microphone,

  // Location
  locationWhenInUse,
  locationAlways,

  // Media & storage
  photos,
  photosAddOnly, // iOS
  videos, // Android 13+
  audio, // Android 13+
  mediaLibrary, // iOS
  accessMediaLocation, // Android
  storage, // Android <13
  manageExternalStorage, // Android

  // People & schedule
  contacts,
  calendarWriteOnly,
  calendarFullAccess,
  reminders, // iOS

  // Connectivity & nearby
  bluetooth,
  bluetoothScan, // Android 12+
  bluetoothAdvertise, // Android 12+
  bluetoothConnect, // Android 12+
  nearbyWifiDevices, // Android 13+

  // Notifications
  notification,
  criticalAlerts, // iOS
  accessNotificationPolicy, // Android

  // Phone, messaging, body
  phone, // Android
  sms, // Android
  sensors,
  sensorsAlways,
  activityRecognition, // Android
  speech, // iOS

  // System & app-level
  appTrackingTransparency, // iOS
  systemAlertWindow, // Android
  requestInstallPackages, // Android
  scheduleExactAlarm, // Android 12+
  ignoreBatteryOptimizations, // Android
  assistant,
}

/// The grant state of a permission.
enum PermissionStatus {
  /// Not yet read.
  unknown,

  /// Granted.
  granted,

  /// Denied, but can be requested again.
  denied,

  /// Denied permanently — the user must change it in app settings.
  permanentlyDenied,

  /// Restricted by the OS (e.g. iOS parental controls).
  restricted,

  /// Partially granted (e.g. iOS limited photo access).
  limited,

  /// Provisionally granted (e.g. iOS provisional notifications).
  provisional,
}

/// Vendor seam for runtime permissions.
///
/// `PermissionsBloc` depends on this interface, never on a platform plugin —
/// which makes it testable without a device: inject a fake whose results you
/// control. The default implementation is `PermissionHandlerProvider`.
abstract class PermissionProvider {
  /// Read the current status without prompting.
  Future<PermissionStatus> status(JuicePermission permission);

  /// Prompt the user and return the resulting status.
  Future<PermissionStatus> request(JuicePermission permission);

  /// Prompt for several permissions at once.
  Future<Map<JuicePermission, PermissionStatus>> requestAll(
      Set<JuicePermission> permissions);

  /// Open the app's system settings page. Returns whether it opened.
  Future<bool> openSettings();

  /// Release any resources held by the provider.
  Future<void> dispose();
}
