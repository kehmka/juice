# juice_permissions

Runtime permission grant-state as a [Juice](https://pub.dev/packages/juice)
bloc — request, check, and react to permissions behind a swappable provider seam.

[![pub package](https://img.shields.io/pub/v/juice_permissions.svg)](https://pub.dev/packages/juice_permissions)
[![License: MIT](https://img.shields.io/badge/license-MIT-purple.svg)](LICENSE)

## What it owns

The grant-state machine for each `JuicePermission` — `granted` / `denied` /
`permanentlyDenied` / `restricted` / `limited` / `provisional`. It does **not**
own the capability behind a permission; capability blocs (location, media,
notifications) react to grant state via per-capability glue packages.

## Install

```yaml
dependencies:
  juice_permissions: ^0.1.0
```

## Use

```dart
import 'package:juice/juice.dart';
import 'package:juice_permissions/juice_permissions.dart';

final permissions = PermissionsBloc.withConfig(PermissionsConfig());

class CameraGate extends StatelessJuiceWidget<PermissionsBloc> {
  CameraGate({super.key})
      : super(groups: {PermissionsGroups.of(JuicePermission.camera)});

  @override
  Widget onBuild(BuildContext context, StreamStatus status) {
    final p = JuicePermission.camera;
    if (bloc.state.isUsable(p)) return const CameraView();
    if (bloc.state.isPermanentlyDenied(p)) {
      return TextButton(
        onPressed: bloc.openAppSettings,
        child: const Text('Enable camera in Settings'),
      );
    }
    return TextButton(
      onPressed: () => bloc.request(p),
      child: const Text('Allow camera'),
    );
  }
}
```

## Status semantics

| Getter | True when |
|--------|-----------|
| `isGranted(p)` | strictly `granted` |
| `isUsable(p)` | `granted` \| `limited` \| `provisional` (use for "can I proceed?") |
| `isPermanentlyDenied(p)` | must be changed in app settings |
| `isRequesting(p)` | a prompt is currently in flight |

## The provider seam (and why it's testable)

`PermissionsBloc` depends on the `PermissionProvider` interface, not on
`permission_handler`. Inject a fake in tests:

```dart
class FakePermissionProvider implements PermissionProvider {
  final Map<JuicePermission, PermissionStatus> grants;
  FakePermissionProvider(this.grants);

  @override
  Future<PermissionStatus> status(JuicePermission p) async =>
      grants[p] ?? PermissionStatus.denied;
  @override
  Future<PermissionStatus> request(JuicePermission p) async =>
      grants[p] ?? PermissionStatus.granted;
  // ...requestAll, openSettings, dispose
}

final bloc = PermissionsBloc.withConfig(
  PermissionsConfig(provider: FakePermissionProvider({...})),
);
```

Singleflight, batch requests, and the permanently-denied → settings flow are all
verified this way, no device required. The only device-touching code,
`PermissionHandlerProvider`, is a thin mapping over `permission_handler`.

## Events

| Event | Effect |
|-------|--------|
| `InitializePermissionsEvent` | configure provider, optionally pre-read a set |
| `CheckPermissionEvent` | read status, no prompt |
| `RequestPermissionEvent` | prompt (singleflight per permission) |
| `RequestPermissionsEvent` | prompt for a batch |
| `OpenAppSettingsEvent` | open OS settings |

## License

MIT License — see [LICENSE](LICENSE).
