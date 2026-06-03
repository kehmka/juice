import 'package:permission_handler/permission_handler.dart' as ph;

import '../permission_provider.dart';

/// Default [PermissionProvider] backed by `permission_handler`.
///
/// Deliberately logic-light: it only maps [JuicePermission] ⇄
/// `permission_handler` types. All behavior (singleflight, state) lives in
/// `PermissionsBloc`, tested with a fake provider — this adapter is verified by
/// inspection and a one-time on-device run.
///
/// Permissions not applicable to the running platform follow `permission_handler`,
/// which generally reports them as granted.
class PermissionHandlerProvider implements PermissionProvider {
  @override
  Future<PermissionStatus> status(JuicePermission permission) async =>
      _mapStatus(await _ph(permission).status);

  @override
  Future<PermissionStatus> request(JuicePermission permission) async =>
      _mapStatus(await _ph(permission).request());

  @override
  Future<Map<JuicePermission, PermissionStatus>> requestAll(
      Set<JuicePermission> permissions) async {
    final result = await permissions.map(_ph).toList().request();
    return {
      for (final p in permissions)
        p: _mapStatus(result[_ph(p)] ?? ph.PermissionStatus.denied),
    };
  }

  @override
  Future<bool> openSettings() => ph.openAppSettings();

  @override
  Future<void> dispose() async {}

  ph.Permission _ph(JuicePermission p) {
    switch (p) {
      case JuicePermission.camera:
        return ph.Permission.camera;
      case JuicePermission.microphone:
        return ph.Permission.microphone;
      case JuicePermission.locationWhenInUse:
        return ph.Permission.locationWhenInUse;
      case JuicePermission.locationAlways:
        return ph.Permission.locationAlways;
      case JuicePermission.photos:
        return ph.Permission.photos;
      case JuicePermission.photosAddOnly:
        return ph.Permission.photosAddOnly;
      case JuicePermission.videos:
        return ph.Permission.videos;
      case JuicePermission.audio:
        return ph.Permission.audio;
      case JuicePermission.mediaLibrary:
        return ph.Permission.mediaLibrary;
      case JuicePermission.accessMediaLocation:
        return ph.Permission.accessMediaLocation;
      case JuicePermission.storage:
        return ph.Permission.storage;
      case JuicePermission.manageExternalStorage:
        return ph.Permission.manageExternalStorage;
      case JuicePermission.contacts:
        return ph.Permission.contacts;
      case JuicePermission.calendarWriteOnly:
        return ph.Permission.calendarWriteOnly;
      case JuicePermission.calendarFullAccess:
        return ph.Permission.calendarFullAccess;
      case JuicePermission.reminders:
        return ph.Permission.reminders;
      case JuicePermission.bluetooth:
        return ph.Permission.bluetooth;
      case JuicePermission.bluetoothScan:
        return ph.Permission.bluetoothScan;
      case JuicePermission.bluetoothAdvertise:
        return ph.Permission.bluetoothAdvertise;
      case JuicePermission.bluetoothConnect:
        return ph.Permission.bluetoothConnect;
      case JuicePermission.nearbyWifiDevices:
        return ph.Permission.nearbyWifiDevices;
      case JuicePermission.notification:
        return ph.Permission.notification;
      case JuicePermission.criticalAlerts:
        return ph.Permission.criticalAlerts;
      case JuicePermission.accessNotificationPolicy:
        return ph.Permission.accessNotificationPolicy;
      case JuicePermission.phone:
        return ph.Permission.phone;
      case JuicePermission.sms:
        return ph.Permission.sms;
      case JuicePermission.sensors:
        return ph.Permission.sensors;
      case JuicePermission.sensorsAlways:
        return ph.Permission.sensorsAlways;
      case JuicePermission.activityRecognition:
        return ph.Permission.activityRecognition;
      case JuicePermission.speech:
        return ph.Permission.speech;
      case JuicePermission.appTrackingTransparency:
        return ph.Permission.appTrackingTransparency;
      case JuicePermission.systemAlertWindow:
        return ph.Permission.systemAlertWindow;
      case JuicePermission.requestInstallPackages:
        return ph.Permission.requestInstallPackages;
      case JuicePermission.scheduleExactAlarm:
        return ph.Permission.scheduleExactAlarm;
      case JuicePermission.ignoreBatteryOptimizations:
        return ph.Permission.ignoreBatteryOptimizations;
      case JuicePermission.assistant:
        return ph.Permission.assistant;
    }
  }

  PermissionStatus _mapStatus(ph.PermissionStatus s) {
    switch (s) {
      case ph.PermissionStatus.granted:
        return PermissionStatus.granted;
      case ph.PermissionStatus.denied:
        return PermissionStatus.denied;
      case ph.PermissionStatus.permanentlyDenied:
        return PermissionStatus.permanentlyDenied;
      case ph.PermissionStatus.restricted:
        return PermissionStatus.restricted;
      case ph.PermissionStatus.limited:
        return PermissionStatus.limited;
      case ph.PermissionStatus.provisional:
        return PermissionStatus.provisional;
    }
  }
}
