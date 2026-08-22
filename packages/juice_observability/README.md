# juice_observability

Crash reporting + breadcrumbs as a [Juice](https://pub.dev/packages/juice) bloc —
with global error capture fanned out to one or more reporters, and a DevTools
mirror that puts the framework's own telemetry on the wire.

[![pub package](https://img.shields.io/pub/v/juice_observability.svg)](https://pub.dev/packages/juice_observability)
[![License: MIT](https://img.shields.io/badge/license-MIT-purple.svg)](LICENSE)

## What it owns

The capture pipeline: global error handlers, a breadcrumb trail, and fan-out to
reporters. It does **not** own a vendor SDK — each `CrashReporter` is an adapter
(Sentry, Crashlytics).

## Install

```yaml
dependencies:
  juice_observability: ^0.3.1
```

## DevTools mirror — `DevtoolsJuiceLogger`

One line puts every structured entry Juice already logs — use-case
executions and completions, state emissions, bloc lifecycle, leak
detection, and all error types — on the VM's extension-event stream as
`juice:<type>` events, live in DevTools and any VM-service listener:

```dart
JuiceLoggerConfig.configureLogger(DevtoolsJuiceLogger());
// or keep your own console logger underneath:
JuiceLoggerConfig.configureLogger(DevtoolsJuiceLogger(inner: myLogger));
```

A decorator on the existing logger seam, not new instrumentation: console
logging keeps working; untyped chatter stays console-only; payloads are
wire-safe (live objects cross as `toString`, capped). With juice ≥ 1.7.0,
starts and ends share an `executionId` with `elapsedMicros` — enough to
draw honest duration spans, even when same-type events overlap under
`concurrent`.

## Use

```dart
final obs = ObservabilityBloc.withConfig(ObservabilityConfig(
  reporters: [MySentryReporter(), if (kDebugMode) ConsoleCrashReporter()],
));

obs.breadcrumb('opened checkout', category: 'nav');
obs.setUser('u_123');

try {
  await risky();
} catch (e, st) {
  obs.recordError(e, st);   // reported with the recent breadcrumbs attached
}
```

## Automatic capture

On init it installs `FlutterError.onError` and `PlatformDispatcher.onError`
(chaining any handlers already set, and restoring them on `close`), so **uncaught**
errors are reported without any `try/catch`. Set `captureUncaught: false` to opt
out (e.g. in tests).

## Breadcrumbs

A bounded ring (`maxBreadcrumbs`, default 50) of recent context, attached to each
report so you can see what led up to a crash. Held on the bloc (race-safe under
rapid logging).

## Writing a reporter

```dart
class MySentryReporter implements CrashReporter {
  @override
  Future<void> recordError(Object error, StackTrace? stack,
      {bool fatal = false, List<Breadcrumb> breadcrumbs = const []}) =>
      Sentry.captureException(error, stackTrace: stack);
  @override
  Future<void> addBreadcrumb(Breadcrumb c) async =>
      Sentry.addBreadcrumb(sentry.Breadcrumb(message: c.message, category: c.category));
  // setUser / setContext / dispose…
}
```

## Fan-out + isolation

Every call fans out to all reporters; a reporter that throws is isolated.

## State

| Field | Meaning |
|---|---|
| `enabled` | capture/reporting on |
| `errorCount` | errors recorded this session |
| `breadcrumbs` | current ring |
| `userId` / `lastError` | current user / last error |

Rebuild group: `observability:status`.

## License

MIT License — see [LICENSE](LICENSE).
