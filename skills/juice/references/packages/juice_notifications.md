---
card_schema: "1.0"
package: juice_notifications
version: 0.2.0
requires:
  juice: ">=1.6.0"
  flutter_local_notifications: ">=17.2.2"
  timezone: ">=0.9.4"
updated: 2026-08-12
---

# juice_notifications — AI card

> Local notification delivery + tap routing as a Juice bloc, behind a swappable
> `NotificationService` seam. Read repo `AGENTS.md` for the Juice mental model +
> gotchas.

## Purpose

**Owns:** local scheduling/display, the tracked `scheduled` set, `lastTap`, and
an informational `permissionGranted` flag.
**Does NOT own:** the permission grant (`juice_permissions` via
`PermissionBinding`), tap *routing* (the app decides), or push/FCM/APNs
(out of scope — planned `PushNotificationSource`).

## Install

```yaml
dependencies:
  juice_notifications: ^0.2.0
```

Default backend is `flutter_local_notifications` — add its platform setup
(Android notification channel/icon, iOS notification capability + usage prompt).
`timezone` powers scheduled delivery.

## Construct

`service` defaults to `LocalNotificationService`. `withConfig` configures the
service, initializes it, and starts listening for taps.

```dart
final notifications = NotificationsBloc.withConfig(NotificationsConfig(
  service: LocalNotificationService(),   // optional; this is the default
));
notifications.show(JuiceNotification(id: 1, title: 'Hi', body: 'There'));
```

## Seams

```dart
abstract class NotificationService {
  Future<void> initialize();                            // channels, tap-handler wiring
  Future<void> show(JuiceNotification n);               // now
  Future<void> schedule(JuiceNotification n, DateTime when);
  Future<void> cancel(int id);
  Future<void> cancelAll();
  Stream<NotificationTap> get taps;                     // delivered → bloc routes
  Future<void> dispose();
}
// JuiceNotification(int id, String title, String body, {String? payload})
// NotificationTap(int id, {String? payload})  // payload = your route / json
```

## API

```dart
void show(JuiceNotification n);                  // immediate; NOT tracked in scheduled
void schedule(JuiceNotification n, DateTime when);  // tracked in scheduled
void cancel(int id);                             // untracks
void cancelAll();
void setPermissionStatus(bool granted);          // wire from juice_permissions
```

## Events

| Event | Concurrency | Effect | Group |
|---|---|---|---|
| `InitializeNotificationsEvent(config)` | `droppable` + shared FIFO | configure, init service, listen for taps | — |
| `ShowNotificationEvent(n)` | `concurrent` dispatcher → shared FIFO | post now (side-effect only) | — |
| `ScheduleNotificationEvent(n, when)` | `concurrent` dispatcher → shared FIFO | schedule + track (replaces same id) | `scheduled` |
| `CancelNotificationEvent(id)` | `concurrent` dispatcher → shared FIFO | cancel + untrack | `scheduled` |
| `CancelAllNotificationsEvent` | `concurrent` dispatcher → shared FIFO | cancel all + clear | `scheduled` |
| `NotificationTappedEvent(tap)` *internal* | `sequential` | record `lastTap` | `tap` |
| `SetPermissionStatusEvent(bool)` | `sequential` | record permission flag | `permission` |

Service mutations enter one bloc-owned FIFO immediately. Per-type sequential
modes cannot preserve ordering between schedule and cancellation event types.

## State

```dart
class NotificationsState extends BlocState {
  List<JuiceNotification> scheduled;   // best-effort local track; OS owns final delivery
  NotificationTap? lastTap;            // app routes on this
  bool permissionGranted;              // informational; OS is final authority
}
```

## Rebuild groups

| Group | Emitted when |
|---|---|
| `NotificationsGroups.scheduled` → `notifications:scheduled` | scheduled set changed |
| `NotificationsGroups.tap` → `notifications:tap` | a notification was tapped |
| `NotificationsGroups.permission` → `notifications:permission` | permission flag changed |

## Recipes

```dart
// 1. Route on tap (selective rebuild → navigate)
class TapRouter extends StatelessJuiceWidget<NotificationsBloc> {
  TapRouter() : super(groups: {NotificationsGroups.tap});
  @override Widget onBuild(BuildContext c, StreamStatus s) {
    final tap = bloc.state.lastTap;
    if (tap?.payload != null) WidgetsBinding.instance.addPostFrameCallback(
        (_) => router.go(tap!.payload!));
    return const SizedBox.shrink();
  }
}

// 2. Custom service (fake / non-default backend)
class FakeService implements NotificationService {
  final shown = <JuiceNotification>[]; final _taps = StreamController<NotificationTap>.broadcast();
  Future<void> initialize() async {}
  Future<void> show(JuiceNotification n) async => shown.add(n);
  Future<void> schedule(JuiceNotification n, DateTime when) async => shown.add(n);
  Future<void> cancel(int id) async {} Future<void> cancelAll() async {}
  Stream<NotificationTap> get taps => _taps.stream;
  Future<void> dispose() async => _taps.close();
  void simulateTap(int id, {String? payload}) => _taps.add(NotificationTap(id: id, payload: payload));
}
```

## Testing

Headless — fake the service, drive the bloc:

```dart
final svc = FakeService();
final n = NotificationsBloc.withConfig(NotificationsConfig(service: svc));
n.schedule(JuiceNotification(id: 1, title: 't', body: 'b'), DateTime(2030));
await settle();                                // Future.delayed(20ms)
expect(n.state.scheduled, hasLength(1));
svc.simulateTap(1, payload: '/home');
await settle();
expect(n.state.lastTap?.payload, '/home');
```

## Failure modes

- `service` calls (`show`/`schedule`/`cancel`) propagate the seam's errors — no
  silent swallow at the use-case layer.
- `scheduled` is **best-effort local tracking**; the OS owns final delivery and
  may cancel/replace independently — never treat it as authoritative.

## Anti-patterns

- ❌ Expecting `show()` to appear in `state.scheduled` — only `schedule()` tracks.
- ❌ Treating `permissionGranted` as the real grant — it's an informational
  mirror; the OS is the authority. Drive it from `juice_permissions`.
- ❌ Routing *inside* this bloc — it records `lastTap`; the app navigates.
- ❌ Adding a `juice_permissions` dependency here — stay agnostic, use the binding.

## Integrates with

- **juice_permissions** — capability-tier; no glue package. Mirror the grant:
  ```dart
  PermissionBinding(permissions, JuicePermission.notification,
    onStatus: (s) => notifications.setPermissionStatus(s == PermissionStatus.granted))..start();
  ```

## Invariants

- `schedule` with an existing id **replaces** that entry in `scheduled`.
- `cancel`/`cancelAll` only emit `scheduled` if the set actually changed.
- `close()` cancels the tap subscription and disposes the service.
- Local-first: push (FCM/APNs) is a separate seam — see ROADMAP.

## See also

`SPEC.md` (design depth) · `README.md` (narrative) · repo `AGENTS.md` (framework).
</content>
