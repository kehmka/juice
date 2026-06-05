# juice_observability example

Crash reporting you can drive by hand, built with Juice primitives only.

Uses a `ConsoleCrashReporter` (prints) so it runs with no backend. Drop
breadcrumbs, record an error (reported with the recent breadcrumbs), or throw an
**uncaught** async error — the installed global handlers capture it
automatically. Watch the counts and the console.

For a real app, add a Sentry/Crashlytics reporter to the `reporters` list.

## Run

```bash
flutter run
```
