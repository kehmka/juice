# juice_analytics example

Event tracking with a consent toggle, built with Juice primitives only.

Uses a `ConsoleAnalyticsSink` (prints to the log) so it runs with no backend.
Tracking starts **off** — flip consent on, then log events / screen views and
watch the counts (and the console). With consent off, events increment the
"dropped" counter instead.

For a real app, add a vendor sink (Firebase/Mixpanel/…) to the `sinks` list.

## Run

```bash
flutter run
```
