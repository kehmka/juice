# Telemetry — the reference (juice 2.0.0)

Everything the framework reports, how it reaches your logger, what it costs,
and how to consume it. The vocabulary is closed and typed: every entry is a
`JuiceTelemetry` with a `JuiceTelemetryKind`, handed to
`JuiceLogger.record`. Free-form lines — yours, through
`BlocUseCase.log` / `logState` / `logError`, and the family packages' — still
travel as a message plus an optional context map through `log` / `logError`.

## 1. The logger

```dart
abstract class JuiceLogger {
  void record(JuiceTelemetry entry);                       // the framework's telemetry
  void log(String message, {Level level, Map<String, dynamic>? context});   // free-form
  void logError(String message, Object error, StackTrace stackTrace,
      {Map<String, dynamic>? context});                    // free-form errors
}
```

Configure one process-wide: `JuiceLoggerConfig.configureLogger(myLogger)`.
The default is `DefaultJuiceLogger` (the `logger` package's pretty printer).

The smallest complete logger forwards telemetry to its own free-form path:

```dart
class MyLogger implements JuiceLogger {
  @override
  void record(JuiceTelemetry e) => e.isError
      ? logError(e.message, e.error!, e.stackTrace ?? StackTrace.empty,
          context: e.toMap())
      : log(e.message, level: e.level, context: e.toMap());

  @override
  void log(String message, {Level level = Level.info, Map<String, dynamic>? context}) { /* … */ }

  @override
  void logError(String message, Object error, StackTrace stackTrace,
      {Map<String, dynamic>? context}) { /* … */ }
}
```

A logger that wants structure switches on `entry.kind` and reads the typed
fields; it never needs `toMap()`.

### The contract

- **Values are live objects.** `state` is the emitted state, `groups` the
  caller's set, `error` the error. Nothing is stringified by the framework.
  Decide whether an entry is kept before touching them.
- **Never retain an entry.** It pins the state it names. Copy what you keep
  as strings or primitives.
- **Errors are the fail-loud path.** An entry with `isError` is delivered
  whatever the floor says; format it eagerly if you like.

## 2. What is built, and when

The framework builds an entry only if `JuiceLoggerConfig.logs(entry.level)`
is true — at or above the global floor `JuiceLoggerConfig.minLevel`, AND at
or above what the configured logger declares it keeps, if it implements
`LevelAwareJuiceLogger`:

```dart
abstract interface class LevelAwareJuiceLogger implements JuiceLogger {
  Level get minLevel;   // read on every gated entry; may change at run time
}
```

`DefaultJuiceLogger` declares exactly what its filter keeps: everything in
debug builds, nothing in profile and release. So an unconfigured app pays
for no chatter in release. `DevtoolsJuiceLogger` (`juice_observability`)
declares everything while a DevTools listener is attached and whatever its
inner logger declares otherwise. A logger that only `implements JuiceLogger`
is treated as keeping everything — implement the interface, or set the
global floor.

Never gated, whatever is declared: every error kind, `emissionAfterClose`,
`eventIgnored`, and a `stateEmitted` entry whose `status` is `failure`.

### Cost

A chatter entry is one object allocation with its fields set; the type
names come from a memo (`Map<Type, String>`). Measured on the benchmark
Mac (`benchmarks/RESULTS.md` §15): the three entries a send produces cost
0.02 µs together (1.13 µs as the context maps they replace); a send is
0.67 µs with the chatter built and consumed by a silent logger, 0.44 µs
with it not built (the release default). A logger that prints pays for its own
formatting — the `DefaultJuiceLogger` formats lazily, so a line the filter
drops costs nothing.

## 3. The vocabulary

Every kind, its wire form (`type` / `action` — the keys `toMap()` emits and
`DevtoolsJuiceLogger` posts as `juice:<type>`), its level, the fields set,
and when it is recorded. Fields not listed are null.

### The use-case span

| kind | type · action | level | fields | when |
|---|---|---|---|---|
| `useCaseStarted` | `use_case_execution` | info | `useCase`, `event`, `executionId` | a use case starts; opens the span |
| `useCaseCompleted` | `use_case_completed` | info | `useCase`, `event`, `executionId`, `elapsedMicros`, `superseded` | the use case returned; closes the span |
| `useCaseFailed` | `use_case_error` | error | `useCase`, `event`, `executionId`, `elapsedMicros`*, `superseded`, `error`, `stackTrace` | the use case threw (or its generator did; then `useCase` is the builder's name); closes the span |
| `sequentialRunFailed` | `use_case_error` | error | `event`, `error`, `stackTrace` | a `sequential` run's failure escaped the executor (an `onError` override that throws); the queue goes on |
| `useCaseSuperseded` | `use_case_superseded` | info | `event`, `cancellable` | a `restartable` run was superseded by a newer same-type event |
| `supersedeFailed` | `use_case_superseded` · `error` | error | `event`, `error`, `stackTrace` | superseding threw (a throwing `cancel()`, logger or binding cancel); the new run still starts |

\* `elapsedMicros` is on the failed span only when the start was logged
(the chatter was on); below the floor only the error line is built.

`executionId` is process-unique and monotonic, so a consumer pairs a start
with its end even when same-type events overlap under `concurrent`. A
thrown use-case error produces TWO entries: `useCaseFailed` (the span's
close) and `blocError` (the bloc's `onError` hook). Span consumers key on
the first, error counters on the second.

### Emissions

| kind | type · action | level | fields | when |
|---|---|---|---|---|
| `stateEmitted` | `state_emission` | info (never gated when `status` is `failure`) | `status`, `state`, `bloc`, `groups`, `event`, `error`* | a status reached the stream |
| `emissionSkipped` | `state_emission_skipped` | info | `bloc`, `event` | `emitUpdate(skipIfSame: true)` found `newState == state` |
| `emissionSuperseded` | `state_emission_superseded` | info | `bloc`, `event`, `status` | the restartable fence dropped an emission or navigation of a superseded run (`status` is `update`, `waiting`, `failure`, `cancel`, `event` or `navigate`) |
| `emissionAfterClose` | `emission_after_close` | warning | `status`, `bloc`, `event`, `error`* | an in-flight use case emitted after its bloc closed; the emit was dropped |

\* `error` is set on a failure emission.

`groups` is the set the caller passed (`null` means every widget). The
event accumulates the groups of every emit made for it: the first emit
adopts the caller's set, later emits merge into a new one.

### The bloc's lifecycle

| kind | type · action | level | fields | when |
|---|---|---|---|---|
| `eventIgnored` | `bloc_lifecycle` · `event_ignored` | warning | `bloc`, `event`, `reason` (`bloc is closed` / `bloc is closing`) | `send` on a closed or closing bloc; the event is refused |
| `blocClosing` | `bloc_lifecycle` · `close` | info | `bloc`, `count` (bindings cancelled; absent from the scope's entry) | `close()` started — one entry from the bloc, one from the scope when it drives the close |
| `blocRegistered` | `bloc_lifecycle` · `register` | info | `bloc`, `lifecycle`, `scope` | `BlocScope.register` |
| `blocCreated` | `bloc_lifecycle` · `create` | info | `bloc`, `lifecycle` | the scope ran a factory |
| `leaseAcquired` | `bloc_lifecycle` · `lease_acquire` | info | `bloc`, `leaseCount` | a lease was taken |
| `leaseReleased` | `bloc_lifecycle` · `lease_release` | info | `bloc`, `leaseCount` | a lease was released |
| `staleLeaseReleased` | `bloc_lifecycle` · `lease_release_stale` | info | `bloc` | a lease on an instance the scope has since replaced was released; ignored |
| `featureScopeEnded` | `bloc_lifecycle` · `end_feature` | info | `scope`, `count` | a feature scope ended its blocs |
| `allBlocsEnded` | `bloc_lifecycle` · `end_all` | info | — | `BlocScope.endAll` |
| `blocCloseFailed` | `bloc_close_error` | error | `bloc`, `error`, `stackTrace` | a bloc's `close()` threw; the scope still cleared its entry and rethrows |

### Errors

| kind | type · action | level | fields | when |
|---|---|---|---|---|
| `blocError` | `bloc_error` | error | `bloc`, `state`, `error`, `stackTrace` | `JuiceBloc.onError`: a use-case error, a stream-binding error, `addError` |
| `errorHandlerFailed` | `error_handler_error` | error | `bloc`, `error`, `stackTrace` | the configured `BlocErrorHandler` threw |
| `unhandledEvent` | `unhandled_event` | error | `bloc`, `event`, `error`, `stackTrace` | an event no use case handles was sent |
| `aviatorError` | `aviator_error` | error | `aviator`, `error`, `stackTrace` | a navigation threw |

### Stream bindings

| kind | type · action | level | fields | when |
|---|---|---|---|---|
| `streamBound` | `stream_binding` · `bind` | info | `bloc`, `key` | `bindStream` listened |
| `streamBindingDone` | `stream_binding` · `done` | info | `bloc`, `key` | the bound stream ended |
| `streamBindingRefused` | `stream_binding` · `refused` | warning when the bloc is closing, info when the run is superseded | `bloc`, `key`, `reason` (`bloc is closed` / `bloc is closing` / `run superseded`) | `bindStream` returned an inert binding |
| `streamBindingError` | `stream_binding` · `error` | error | `bloc`, `key`, `error`, `stackTrace` | the stream errored and the binding has no `onError` of its own; the bloc's `onError` runs and the binding is cancelled unless `cancelOnError: false` |
| `streamBindingCallbackError` | `stream_binding` · `callback_error` | error | `bloc`, `key`, `callback` (`onData` / `onError` / `onDone`), `error`, `stackTrace` | a binding callback threw; the bloc's `onError` runs; an `onData` throw leaves the binding active |
| `streamBindingCancelError` | `stream_binding` · `cancel_error` | error | `bloc`, `key`, `reason` (`at unbind` / `at close` / `at supersede` / `on error`), `error`, `stackTrace` | a subscription's cancel threw; logged, never uncaught |

### Builders and relays

| kind | type · action | level | fields | when |
|---|---|---|---|---|
| `retryAbandoned` | `retry_abandoned` | info | `bloc`, `attempt` | `RetryableUseCaseBuilder` stopped because the bloc closed during a backoff |
| `eventSubscriptionInitialized` | `event_subscription` · `initialize` | info | `sourceBloc`, `sourceEvent`, `localEvent` | an `EventSubscription` subscribed to its source |
| `eventSubscriptionTriggered` | `event_subscription` · `trigger` | info | `sourceBloc`, `sourceEvent`, `localEvent` | a source event was forwarded as a local one |
| `eventSubscriptionClosed` | `event_subscription` · `close` | info | `sourceBloc`, `sourceEvent` | the subscription closed |
| `leakDetectionEnabled` | `leak_detection` · `enable` | info | — | `BlocScope.enableLeakDetection` |

Free-form error lines the framework still emits through `logError` (no
kind): a relay's initialisation failure, a relay's transformer or stream
error, an `EventSubscription`'s transformer or stream error. They name the
blocs in the message.

## 4. The DevTools wire

`DevtoolsJuiceLogger` posts every recorded entry as a VM extension event
`juice:<type>` whose payload is `toMap()` without `type`, plus `message` and
`level`, plus `error` and `stackTrace` for error entries, every value
clipped to 512 characters. The `juice_observability` DevTools extension
consumes that stream. Free-form lines post only when their context carries a
`type`.

## 5. Testing against telemetry

`juiceTest` counts `useCaseFailed` and the three binding-error kinds into
its `errors:` expectation, and fails a test on `emissionAfterClose` or a
span left open at close. For your own assertions, a recording logger is a
dozen lines:

```dart
class RecordingLogger implements JuiceLogger {
  final entries = <JuiceTelemetry>[];
  @override
  void record(JuiceTelemetry e) => entries.add(e);
  @override
  void log(String m, {Level level = Level.info, Map<String, dynamic>? context}) {}
  @override
  void logError(String m, Object e, StackTrace s, {Map<String, dynamic>? context}) {}
}

final spans = log.entries.where((e) => e.kind == JuiceTelemetryKind.useCaseCompleted);
```

## 6. Coming from 1.x

Every entry used to be `log(message, context: {'type': …, …})` or
`logError(…, context: {'type': …})`. In 2.0.0 it is `record(entry)`;
`entry.toMap()` is that map (same keys and values: `type`, `action`, and the
fields), `entry.message` is that message, `entry.level` that level. Two
keys changed name: the bloc close entry's `streamBindings` and the feature
scope's `blocsEnded` are both `count`. The duplicate `use_case_error` line
without an `executionId` is gone; the error still reaches `blocError`.
`doc/guides/upgrading-to-2.0.md` has the logger migration in full.
