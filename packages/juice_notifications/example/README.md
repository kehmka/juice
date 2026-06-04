# juice_notifications example

Schedule / cancel local notifications and toggle permission status, built with
Juice primitives only.

Uses a no-op `DemoNotificationService` (the `NotificationService` seam) so the
app runs with **no plugin, timezone setup, or device** — the bloc's tracking and
tap routing work end-to-end against the fake. The screen is a
`StatelessJuiceWidget` bound to the notification rebuild groups.

For a real app, swap the service for the default and wire permissions:

```dart
final notifications = NotificationsBloc.withConfig(NotificationsConfig());

// from juice_permissions:
PermissionBinding(permissions, JuicePermission.notification,
  onStatus: (s) => notifications.setPermissionStatus(s == PermissionStatus.granted),
)..start();
```

## Run

```bash
flutter run
```
