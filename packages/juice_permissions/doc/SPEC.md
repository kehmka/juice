# juice_permissions Specification

> **Status:** Implemented (shipping).
> **Package:** `juice_permissions`
> **Primary Bloc:** `PermissionsBloc`

## Overview

`juice_permissions` is the **shared** grant-state bloc. Capability blocs
(location, media, notifications) do not own permission handling themselves; they
react to this bloc's state via per-capability glue packages
(`juice_location_permissions`, …). One grant state machine, not four.

## Domain boundary

- **Owns:** the grant-state machine (`granted`/`denied`/`permanentlyDenied`/
  `restricted`/`limited`/`provisional`) per `JuicePermission`.
- **Does NOT own:** the capability behind the permission, or the policy of what
  to do when denied.

## Dependencies

| Package | Why |
|---------|-----|
| `juice` | core bloc infrastructure |
| `permission_handler` | default provider's platform source |

No `juice_storage` — the OS is the source of truth; nothing is persisted.

## Vendor seam

`PermissionProvider` is the swap point. The bloc depends on the interface, not
`permission_handler`, which is what makes it testable without a device.

```dart
abstract class PermissionProvider {
  Future<PermissionStatus> status(JuicePermission p);
  Future<PermissionStatus> request(JuicePermission p);
  Future<Map<JuicePermission, PermissionStatus>> requestAll(Set<JuicePermission> ps);
  Future<bool> openSettings();
  Future<void> dispose();
}
```

`JuicePermission` is a vendor-agnostic enum covering the full `permission_handler`
set (the deprecated `calendar`/`location` umbrellas are replaced by their split
values). Permissions not applicable to the running platform follow
`permission_handler`, which generally reports them as `granted`.

## State

```dart
class PermissionsState extends BlocState {
  final Map<JuicePermission, PermissionStatus> statuses;  // absent → unknown
  final Set<JuicePermission> inFlight;                    // prompts in progress
  PermissionStatus statusOf(p);
  bool isGranted(p);              // strictly granted
  bool isUsable(p);              // granted | limited | provisional
  bool isPermanentlyDenied(p);
  bool isRequesting(p);
}
```

## Events

| Event | Effect | Groups |
|-------|--------|--------|
| `InitializePermissionsEvent(config)` | store provider, optionally pre-read `precheck` | `permissions:status`, per-permission |
| `CheckPermissionEvent(p)` | read status, no prompt | `permissions:status`, `permissions:status:<p>` |
| `RequestPermissionEvent(p)` | prompt (singleflight per permission) | above + `permissions:inflight` |
| `RequestPermissionsEvent(set)` | batch prompt (no singleflight) | as above |
| `OpenAppSettingsEvent` | open OS settings | — |

## Singleflight

Concurrent `RequestPermissionEvent`s for the same permission collapse to one OS
prompt via `PermissionsBloc.requestsInFlight` (a per-permission `Completer` map);
`state.inFlight` mirrors it for the UI. Batch requests do not coalesce.

## Testing

`PermissionsBloc` is tested with a fake `PermissionProvider`: request/deny/
permanently-denied flows, per-permission singleflight (concurrent requests → one
provider call), batch, and the settings delegation all run headlessly. The only
device-touching code, `PermissionHandlerProvider`, is a thin enum/status mapping
verified by inspection and a one-time on-device run.

## Spec Version

| Version | Date | Status |
|---------|------|--------|
| 1.0 | 2026-05-28 | Implemented |
