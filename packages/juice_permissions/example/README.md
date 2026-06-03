# juice_permissions example

A list of permissions with live status and request buttons, built with Juice
primitives only.

A `DemoPermissionProvider` simulates the OS response (first request grants;
`notification` is configured to come back permanently denied to show the
"open Settings" path), so the app runs with **no device or real prompts** — the
same provider seam a real adapter (`PermissionHandlerProvider`) plugs into.

Each row is a `StatelessJuiceWidget` bound to its own
`permissions:status:<name>` group, so requesting the camera doesn't rebuild the
microphone row. State lives entirely in the bloc.

For a real app, swap the provider for the default:

```dart
PermissionsBloc.withConfig(PermissionsConfig()); // PermissionHandlerProvider
```

## Run

```bash
flutter run
```
