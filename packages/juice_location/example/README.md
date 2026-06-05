# juice_location example

Get-current + continuous tracking, built with Juice primitives only.

Uses a `DemoLocationSource` (the `LocationSource` seam) that emits a wandering
position on a timer, so the app runs with **no GPS or device**. The screen is a
`StatelessJuiceWidget` bound to the location rebuild groups.

For a real app, swap the source for the default and wire permissions:

```dart
final location = LocationBloc.withConfig(LocationConfig());

// from juice_permissions:
PermissionBinding(permissions, JuicePermission.locationWhenInUse,
  onStatus: (s) => location.setPermissionStatus(s == PermissionStatus.granted),
)..start();
```

## Run

```bash
flutter run
```
