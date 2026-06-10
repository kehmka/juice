---
card_schema: "1.0"
package: juice_permissions
version: 0.2.0
requires:
  juice: ">=1.4.0"
  permission_handler: ">=11.3.0"
updated: 2026-06-09
---

# juice_permissions — AI card

> Runtime permission grant-state as a bloc: request, check, and react to
> permissions behind a swappable provider seam. The **shared** grant-state
> machine — capability blocs (location, media, notifications) react via the
> `PermissionBinding` helper, not a per-capability glue package. Read repo
> `AGENTS.md` for the Juice mental model + gotchas.

## Purpose

**Owns:** the grant-state machine per `JuicePermission`
(granted/denied/permanentlyDenied/restricted/limited/provisional).
**Does NOT own:** the capability behind a permission, or the policy of what to do
when denied. Nothing is persisted — the OS is the source of truth.

## When to use

Any time a feature needs a runtime permission. One bloc holds every permission's
status; capability blocs subscribe to *their* permission via `PermissionBinding`
instead of duplicating permission logic.

## Install

```yaml
dependencies:
  juice_permissions: ^0.2.0   # pulls permission_handler for the default provider
```

Declare the underlying OS permissions you actually use in `Info.plist` /
`AndroidManifest.xml` per `permission_handler`'s setup.

## Construct

Provider is **optional** — defaults to `PermissionHandlerProvider`:

```dart
final permissions = PermissionsBloc.withConfig(PermissionsConfig(
  // provider: FakePermissionProvider(),         // optional; default = permission_handler
  precheck: {JuicePermission.camera, JuicePermission.notification}, // read (no prompt) at init
));
```

## Seams

```dart
// Vendor seam. OPTIONAL (default PermissionHandlerProvider).
abstract class PermissionProvider {
  Future<PermissionStatus> status(JuicePermission p);                       // no prompt
  Future<PermissionStatus> request(JuicePermission p);                      // prompts
  Future<Map<JuicePermission, PermissionStatus>> requestAll(Set<JuicePermission> ps);
  Future<bool> openSettings();                                              // → did it open
  Future<void> dispose();
}
```

`JuicePermission` is a vendor-agnostic enum covering the full `permission_handler`
set (split values, not the deprecated `calendar`/`location` umbrellas).
Permissions not applicable to the running platform generally report `granted`.

## API

```dart
void check(JuicePermission p);                 // read status, no prompt
void request(JuicePermission p);               // prompt (singleflight per permission)
void requestAll(Set<JuicePermission> ps);      // batch prompt (NO singleflight)
void openAppSettings();                        // open OS settings page
PermissionProvider get provider;
```

## Events

| Event | Effect | Groups |
|---|---|---|
| `InitializePermissionsEvent(config)` | store provider, pre-read `precheck` | `permissions:status`, per-permission |
| `CheckPermissionEvent(p)` | read status, no prompt | `permissions:status`, `permissions:status:<p>` |
| `RequestPermissionEvent(p)` | prompt (singleflight per permission) | above + `permissions:inflight` |
| `RequestPermissionsEvent(set)` | batch prompt (no coalescing) | as above |
| `OpenAppSettingsEvent` | open OS settings | — |

## State

```dart
class PermissionsState extends BlocState {
  final Map<JuicePermission, PermissionStatus> statuses;  // absent → unknown
  final Set<JuicePermission> inFlight;                    // prompts in progress
  PermissionStatus statusOf(JuicePermission p);
  bool isGranted(JuicePermission p);            // strictly granted
  bool isUsable(JuicePermission p);             // granted | limited | provisional  ← "can I proceed?"
  bool isPermanentlyDenied(JuicePermission p);  // must change in app settings
  bool isRequesting(JuicePermission p);
  static const initial = PermissionsState();
}
// PermissionStatus { unknown, granted, denied, permanentlyDenied, restricted, limited, provisional }
```

## Rebuild groups

| Group | Emitted when |
|---|---|
| `PermissionsGroups.status` → `permissions:status` | any permission status changed |
| `PermissionsGroups.inFlight` → `permissions:inflight` | the in-flight request set changed |
| `PermissionsGroups.of(p)` → `permissions:status:<p.name>` | that one permission's status changed |

## Concurrency

`RequestPermissionEvent` is **singleflight per permission**: concurrent requests
for the same `JuicePermission` share one OS prompt via
`PermissionsBloc.requestsInFlight` (a per-permission `Completer` map, authoritative);
`state.inFlight` mirrors it for the UI. `requestAll`/`RequestPermissionsEvent`
batch requests do **not** coalesce.

## Recipes

```dart
// 1. Gate a feature on a permission (rebuild only when camera's status changes)
class CameraGate extends StatelessJuiceWidget<PermissionsBloc> {
  CameraGate({super.key}) : super(groups: {PermissionsGroups.of(JuicePermission.camera)});
  @override Widget onBuild(BuildContext c, StreamStatus s) {
    if (bloc.state.isUsable(JuicePermission.camera)) return const CameraView();
    if (bloc.state.isPermanentlyDenied(JuicePermission.camera)) {
      return TextButton(onPressed: bloc.openAppSettings, child: const Text('Open settings'));
    }
    return TextButton(
      onPressed: () => bloc.request(JuicePermission.camera), child: const Text('Allow camera'));
  }
}

// 2. PermissionBinding — how a capability bloc reacts WITHOUT a glue package.
//    The capability bloc exposes its own neutral status setter; map it here.
final binding = PermissionBinding(
  permissionsBloc,
  JuicePermission.notification,
  onStatus: (status) => notificationsBloc.setPermissionStatus(
    status == PermissionStatus.granted),
  emitInitial: true,            // fire onStatus once with the current status on start()
)..start();
// ... on teardown
binding.dispose();
```

`PermissionBinding` depends only on `juice_permissions` (it talks through a
callback), so the capability bloc never imports this package.

## Testing

Headless — fake the provider; assert flows + singleflight:

```dart
class FakePermissionProvider implements PermissionProvider {
  final results = <JuicePermission, PermissionStatus>{};
  int requestCalls = 0;
  @override Future<PermissionStatus> status(JuicePermission p) async =>
      results[p] ?? PermissionStatus.denied;
  @override Future<PermissionStatus> request(JuicePermission p) async {
    requestCalls++;
    await Future<void>.delayed(const Duration(milliseconds: 5));
    return results[p] = PermissionStatus.granted;
  }
  @override Future<Map<JuicePermission, PermissionStatus>> requestAll(Set<JuicePermission> ps) async =>
      {for (final p in ps) p: PermissionStatus.granted};
  @override Future<bool> openSettings() async => true;
  @override Future<void> dispose() async {}
}

final fake = FakePermissionProvider();
final bloc = PermissionsBloc.withConfig(PermissionsConfig(provider: fake));
bloc.request(JuicePermission.camera);
bloc.request(JuicePermission.camera);   // concurrent → same prompt
await settle();
expect(fake.requestCalls, 1);                                  // singleflight
expect(bloc.state.isUsable(JuicePermission.camera), isTrue);
```

## Failure modes

- A `provider.request` throw → `RequestPermissionUseCase` emits a **failure**,
  clears `inFlight` for that permission, and completes the in-flight completer
  with the error (joined callers don't re-throw — surfaced by the first caller).
- `precheck` runs sequentially at init; a throwing `status()` fails initialization.
- Status is never assumed — an unread permission is `unknown`, not `denied`.

## Anti-patterns

- ❌ Using `isGranted` for "can I proceed?" — iOS `limited`/`provisional` are
  usable; use `isUsable`.
- ❌ Re-prompting a `permanentlyDenied` permission — it won't show a dialog;
  route to `openAppSettings()`.
- ❌ Building a per-capability permission glue package — use `PermissionBinding`.
- ❌ A capability bloc importing `juice_permissions` directly — go through the
  binding's callback so the dependency stays one-way.

## Integrates with

- **Any capability bloc** (notifications, location, media) — via
  `PermissionBinding(permissions, JuicePermission.x, onStatus: ...)`.
- **juice_lifecycle** — re-`check()` permissions on `resumedFromBackground`
  (the user may have toggled them in Settings).

## Invariants

- One grant-state machine for the whole app — capabilities never own their own.
- `requestsInFlight` (the Completer map) is authoritative for coalescing;
  `state.inFlight` is its UI mirror.
- Per-permission groups (`permissions:status:<name>`) let widgets rebuild on one
  permission without thrashing on unrelated ones.

## See also

`SPEC.md` (design) · `README.md` (narrative) · repo `AGENTS.md` (framework).
