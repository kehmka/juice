# juice_notifications

Local notification delivery and tap routing as a
[Juice](https://pub.dev/packages/juice) bloc, behind a swappable service seam.

[![pub package](https://img.shields.io/pub/v/juice_notifications.svg)](https://pub.dev/packages/juice_notifications)
[![License: MIT](https://img.shields.io/badge/license-MIT-purple.svg)](LICENSE)

## What it owns

Local notification scheduling/display, the tracked `scheduled` set, and the
last-tapped payload (for routing). It does **not** own the permission *grant*
(that's `juice_permissions`, wired via `PermissionBinding`), or what to do on a
tap (the app routes it).

> **Local-first.** Push (FCM/APNs) is out of scope for 0.1 — a separate
> `PushNotificationSource` seam is planned.

## Install

```yaml
dependencies:
  juice_notifications: ^0.1.0
```

The default service uses `flutter_local_notifications`; for scheduling, call
`tz.initializeTimeZones()` (from the `timezone` package) once at startup and
declare a notification icon per that plugin's setup.

## Use

```dart
import 'package:juice/juice.dart';
import 'package:juice_notifications/juice_notifications.dart';

final notifications = NotificationsBloc.withConfig(NotificationsConfig());

notifications.show(JuiceNotification(id: 1, title: 'Hi', body: 'There'));
notifications.schedule(
  JuiceNotification(id: 2, title: 'Reminder', body: 'Later'),
  DateTime.now().add(const Duration(hours: 1)),
);
notifications.cancel(2);
```

## Reacting to taps

```dart
class TapRouter extends StatelessJuiceWidget<NotificationsBloc> {
  TapRouter({super.key}) : super(groups: {NotificationsGroups.tap});
  @override
  Widget onBuild(BuildContext context, StreamStatus status) {
    final tap = bloc.state.lastTap;
    // route on tap?.payload …
    return const SizedBox.shrink();
  }
}
```

## Permissions (via juice_permissions)

The bloc stays permission-agnostic — it holds a `permissionGranted` flag set
through `setPermissionStatus`. Wire it from `juice_permissions` with the generic
binding:

```dart
PermissionBinding(permissions, JuicePermission.notification,
  onStatus: (s) => notifications.setPermissionStatus(s == PermissionStatus.granted),
)..start();
```

No `juice_permissions` dependency leaks into this package — the callback decouples it.

## The seam (and why it's testable)

`NotificationsBloc` depends on `NotificationService`, not on a plugin. Inject a
fake in tests to drive show/schedule/cancel/taps headlessly; the only
device-touching code, `LocalNotificationService`, is a thin mapping.

## License

MIT License — see [LICENSE](LICENSE).
