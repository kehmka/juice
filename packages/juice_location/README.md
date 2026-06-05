# juice_location

Device location — one-shot reads and continuous tracking — as a
[Juice](https://pub.dev/packages/juice) bloc, behind a swappable source seam.

[![pub package](https://img.shields.io/pub/v/juice_location.svg)](https://pub.dev/packages/juice_location)
[![License: MIT](https://img.shields.io/badge/license-MIT-purple.svg)](LICENSE)

## What it owns

The current `GeoPosition` and whether tracking is active. It does **not** own the
permission *grant* (that's `juice_permissions`, via `PermissionBinding`), or maps
/ geocoding.

## Install

```yaml
dependencies:
  juice_location: ^0.1.0
```

The default source uses `geolocator` — follow its platform setup (Info.plist /
AndroidManifest permission strings).

## Use

```dart
import 'package:juice/juice.dart';
import 'package:juice_location/juice_location.dart';

final location = LocationBloc.withConfig(LocationConfig());

location.getCurrent();             // one-shot
location.startTrackingUpdates();   // continuous
location.stopTrackingUpdates();

class Coords extends StatelessJuiceWidget<LocationBloc> {
  Coords({super.key}) : super(groups: {LocationGroups.position});
  @override
  Widget onBuild(BuildContext context, StreamStatus status) {
    final p = bloc.state.current;
    return Text(p == null ? '—' : '${p.latitude}, ${p.longitude}');
  }
}
```

## Permissions (via juice_permissions)

The bloc stays permission-agnostic — it holds `permissionGranted`, set through
`setPermissionStatus`. Wire it from `juice_permissions`:

```dart
PermissionBinding(permissions, JuicePermission.locationWhenInUse,
  onStatus: (s) => location.setPermissionStatus(s == PermissionStatus.granted),
)..start();
```

No `juice_permissions` dependency leaks in — the callback decouples it.

## State

| Field | Meaning |
|-------|---------|
| `current` | latest `GeoPosition` (null before first fix) |
| `tracking` | continuous tracking active |
| `permissionGranted` | externally-set flag |
| `lastError` | last read error |

## The seam (and why it's testable)

`LocationBloc` depends on `LocationSource` (`current()` + `positions()` stream),
not on a plugin. Inject a fake to drive reads/tracking headlessly; the only
device-touching code, `GeolocatorLocationSource`, is a thin mapping.

## License

MIT License — see [LICENSE](LICENSE).
