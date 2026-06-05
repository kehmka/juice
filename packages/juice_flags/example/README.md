# juice_flags example

Feature flags driving the UI, built with Juice primitives only.

A `DemoFlagsSource` (the `FlagsSource` seam) serves an initial map and flips
`promo_banner` every 3 seconds over its live stream — so you can watch **only
that flag's widget rebuild** while the others stay put. That's the per-flag
selective refresh.

Demonstrates:
- per-flag widgets (`FlagsGroups.flag(key)`)
- typed reads with defaults (`boolFlag`/`stringFlag`/`intFlag`)
- a local override toggle (`setFlagOverride`)
- live updates via `changes()`

For a real app, swap `DemoFlagsSource` for a remote adapter (e.g. a Firebase
Remote Config `FlagsSource` — see the package README).

## Run

```bash
flutter run
```
