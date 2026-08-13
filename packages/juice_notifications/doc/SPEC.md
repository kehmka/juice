# juice_notifications Specification

> **Status:** Implemented (shipping, local-first).
> **Package:** `juice_notifications`
> **Primary Bloc:** `NotificationsBloc`

## Overview

A **capability-tier** bloc owning local notification delivery and tap routing.
The first package to use the shared-permissions pattern: it exposes a neutral
`setPermissionStatus` rather than depending on `juice_permissions`.

## Domain boundary

- **Owns:** local scheduling/display, the tracked `scheduled` set, `lastTap`,
  and an informational `permissionGranted` flag.
- **Does NOT own:** the permission grant (`juice_permissions` via
  `PermissionBinding`), tap routing (the app), or push (planned `PushNotificationSource`).

## Dependencies

| Package | Why |
|---------|-----|
| `juice` | core bloc infrastructure |
| `flutter_local_notifications` | default service backend |
| `timezone` | `zonedSchedule` for scheduling |

No `juice_permissions` dependency — permission status arrives via
`setPermissionStatus` (decoupled by `PermissionBinding`'s callback).

## Seam

`NotificationService`: `initialize`, `show`, `schedule(when)`, `cancel(id)`,
`cancelAll`, `Stream<NotificationTap> taps`, `dispose`. Default
`LocalNotificationService` (flutter_local_notifications). Fake in tests.

`JuiceNotification { int id; String title, body; String? payload }` ·
`NotificationTap { int id; String? payload }`.

## State

```dart
class NotificationsState extends BlocState {
  final List<JuiceNotification> scheduled;  // tracked future notifications
  final NotificationTap? lastTap;
  final bool permissionGranted;             // set externally
  static const initial = NotificationsState();
}
```

`show()` is immediate (not tracked); `schedule()` adds to `scheduled`;
`cancel`/`cancelAll` remove. Taps from the service stream become `lastTap`.

## Events

| Event | Concurrency | Effect | Groups |
|-------|-------------|--------|--------|
| `InitializeNotificationsEvent(config)` | `droppable` + shared FIFO | configure, init service, listen for taps | — |
| `ShowNotificationEvent` | `concurrent` dispatcher → shared FIFO | post now | — |
| `ScheduleNotificationEvent(n, when)` | `concurrent` dispatcher → shared FIFO | schedule + track | `notifications:scheduled` |
| `CancelNotificationEvent(id)` / `CancelAllNotificationsEvent` | `concurrent` dispatcher → shared FIFO | cancel + untrack | `notifications:scheduled` |
| `NotificationTappedEvent` | `sequential` | internal — record tap | `notifications:tap` |
| `SetPermissionStatusEvent(granted)` | `sequential` | record permission (from `PermissionBinding`) | `notifications:permission` |

Initialization and all service mutations share one bloc-owned FIFO. Dispatcher
execution stays concurrent for those event types so every operation enters the
cross-event queue immediately and global send order is retained.

## Permissions

Stays agnostic: holds `permissionGranted`, set via `setPermissionStatus`. Wire
from `juice_permissions`:

```dart
PermissionBinding(permissions, JuicePermission.notification,
  onStatus: (s) => notifications.setPermissionStatus(s == PermissionStatus.granted))..start();
```

This validates the shared-permissions decision: one shared bloc, a generic
binding, no per-capability glue package.

## Testing

Headless with a fake `NotificationService`: show/schedule/cancel/cancelAll,
cross-event service ordering, tap surfacing, permission flag, dispose. The device-touching
`LocalNotificationService` is verified by inspection + one on-device run.

## Spec Version

| Version | Date | Status |
|---------|------|--------|
| 1.1 | 2026-08-12 | Juice 1.6 policy + cross-event service FIFO |
| 1.0 | 2026-05-28 | Implemented (local-first) |
