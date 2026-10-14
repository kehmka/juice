# Telemetry — the reference (juice 2.0.0)

Everything the framework reports, how it reaches your logger, what it costs,
and how to consume it. The vocabulary is closed and typed: every entry is a
`JuiceTelemetry` with a `JuiceTelemetryKind`, handed to
`JuiceLogger.record`. Free-form lines — yours, through `BlocUseCase.log` /
`logState` / `logError`, and the family packages' — travel as a message plus
an optional context map through `log` / `logError`. The core framework
itself emits no free-form line.

## 1. The logger

```dart
abstract class JuiceLogger {
  void record(JuiceTelemetry entry);                              // the framework's telemetry
  void log(String message,
      {Level level = Level.info, Map<String, dynamic>? context});  // free-form
  void logError(String message, Object error, StackTrace stackTrace,
      {Map<String, dynamic>? context});                           // free-form errors
}
```

Configure one process-wide: `JuiceLoggerConfig.configureLogger(myLogger)`.
The default is `DefaultJuiceLogger` (the `logger` package's pretty printer).

The `record` of the smallest complete logger forwards telemetry to its own
free-form path:

```dart
class MyLogger implements JuiceLogger {
  @override
  void record(JuiceTelemetry e) => e.isError
      ? logError(e.message, e.error!, e.stackTrace ?? StackTrace.empty,
          context: e.toMap())
      : log(e.message, level: e.level, context: e.toMap());

  @override
  void log(String message,
      {Level level = Level.info, Map<String, dynamic>? context}) { /* … */ }

  @override
  void logError(String message, Object error, StackTrace stackTrace,
      {Map<String, dynamic>? context}) { /* … */ }
}
```

A logger that wants structure switches on `entry.kind` and reads the typed
fields; it never needs `toMap()`. `record` is called synchronously on the
thread that produced the entry, and a throw from it is not caught.

### The contract

- **Values are live objects.** `state` is the emitted state, `groups` the
  caller's set, `error` the error. Nothing is stringified by the framework.
  Decide whether an entry is kept before touching them.
- **Never retain an entry.** It pins the state it names. Copy what you keep
  as strings or primitives.
- **Every error kind carries `error`** (and a `stackTrace` where one
  exists), so `e.error!` on an `isError` entry is safe. A failure emission
  also carries `error` and `stackTrace` but is not an error entry: it is a
  `stateEmitted` at info.

## 2. What is built, and when

The framework builds an entry only if `JuiceLoggerConfig.logs(level)` is
true — at or above the global floor `JuiceLoggerConfig.minLevel`, AND at or
above what the configured logger declares it keeps, if it implements
`LevelAwareJuiceLogger`:

```dart
abstract interface class LevelAwareJuiceLogger implements JuiceLogger {
  Level get minLevel;   // read on every gated entry; may change at run time
}
```

`DefaultJuiceLogger` declares exactly what its filter keeps: everything in
debug builds, nothing in profile and release. So an unconfigured app pays
for no chatter in release. `DefaultJuiceLogger(logger: myLogger)` with a
caller-supplied `Logger` declares everything (its filter is unknown) and
formats eagerly. `DevtoolsJuiceLogger` (`juice_observability`) declares
everything while a DevTools listener is attached and whatever its inner
logger declares otherwise. A logger that only `implements JuiceLogger` is
treated as keeping everything — implement the interface, or set the global
floor.

**Recorded whatever the floor says:** every error kind, `emissionAfterClose`,
`eventIgnored`, `leasedBlocGot`, `streamBindingRefused`, and a `stateEmitted`
whose `status` is `failure`. Every other kind is gated at its level.

### Cost

A chatter entry is one object allocation with its fields set; the type names
come from a memo (`Map<Type, String>`). On the benchmark Mac
(`benchmarks/RESULTS.md` §16–§17b) a send is 0.66 µs with the chatter built
and consumed by a silent logger and 0.44 µs with it not built (the release
default); the three entries a send produces are priced alone in §17b,
against the context maps they replace. A logger that prints pays for its own
formatting — `DefaultJuiceLogger` formats lazily, so a line its filter drops
costs nothing.

## 3. The vocabulary

Every kind, its wire form (`type` · `action` — the keys `toMap()` emits and
`DevtoolsJuiceLogger` posts as `juice:<type>`), its level, the fields set,
and when it is recorded. Fields not listed are null. `message` is a constant
per kind: the facts are the fields.

### The use-case span

| kind | type · action | level | fields | when |
|---|---|---|---|---|
| `useCaseStarted` | `use_case_execution` | info | `useCase`, `event`, `executionId` | a use case is about to execute; opens the span |
| `useCaseCompleted` | `use_case_completed` | info | `useCase`, `event`, `executionId`, `elapsedMicros`, `superseded` | the use case returned; closes the span |
| `useCaseFailed` | `use_case_error` | error | `useCase`, `event`, `executionId`, `elapsedMicros`*, `superseded`, `error`, `stackTrace` | the use case threw, or its generator did (then `useCase` is the builder's name and no start was recorded); closes the span |
| `sequentialRunFailed` | `sequential_run_error` | error | `event`, `error`, `stackTrace` | a `sequential` run's failure escaped the executor (an `onError` override that throws); the queue goes on; no span |
| `useCaseSuperseded` | `use_case_superseded` | info | `event`, `cancellable` | a `restartable` run was superseded by a newer same-type event |
| `supersedeFailed` | `supersede_error` | error | `event`, `error`, `stackTrace` | superseding threw (a throwing `cancel()`, logger or binding cancel); the new run still starts |

\* `elapsedMicros` is set when the span was being timed — the chatter was on
when the use case started — whether or not a start entry was recorded.

`executionId` is process-unique and monotonic, so a consumer pairs a start
with its end even when same-type events overlap under `concurrent`. A thrown
use-case error produces TWO entries: `useCaseFailed` (the span's close) and
`blocError` (the bloc's `onError` hook). Span consumers key on the first,
error counters on the second.

### Emissions

| kind | type · action | level | fields | when |
|---|---|---|---|---|
| `stateEmitted` | `state_emission` | info (never gated when `status` is `failure`) | `status`, `state`, `bloc`, `groups`, `event`; `error`, `stackTrace` on a failure | a status is being put on the stream |
| `emissionSkipped` | `state_emission_skipped` | info | `bloc`, `event` | `emitUpdate(skipIfSame: true)` found `newState == state` |
| `emissionSuperseded` | `state_emission_superseded` | info | `bloc`, `event`, `status` (`update`, `waiting`, `failure`, `cancel`, `event` or `navigate`) | the restartable fence dropped an emission or navigation of a superseded run |
| `emissionAfterClose` | `emission_after_close` | warning | `status`, `bloc`, `event`; `error` on a failure | an in-flight use case emitted after its bloc closed; the emit was dropped |

`status` is an `EmissionKind`; its `wire` string is what `toMap()` emits.
`groups` is the set the caller passed (`null` means every widget). The
event accumulates the groups of every emit made for it: the first emit
adopts the caller's set, later emits merge into a new one.

### The bloc's lifecycle

| kind | type · action | level | fields | when |
|---|---|---|---|---|
| `eventIgnored` | `bloc_lifecycle` · `event_ignored` | warning | `bloc`, `event`, `reason` (`bloc is closed` / `bloc is closing`) | `send` on a closed or closing bloc; the event is refused |
| `blocCloseStarted` | `bloc_lifecycle` · `close` | info | `bloc`, `bindingCount` | `close()` started; one entry per bloc |
| `blocRegistered` | `bloc_lifecycle` · `register` | info | `bloc`, `lifecycle`, `scope` (the key, `global` when none) | `BlocScope.register` registered a new type (a repeat registration records nothing) |
| `blocCreated` | `bloc_lifecycle` · `create` | info | `bloc`, `lifecycle` | the scope ran a factory |
| `leaseAcquired` | `bloc_lifecycle` · `lease_acquire` | info | `bloc`, `leaseCount` | a lease was taken |
| `leaseReleased` | `bloc_lifecycle` · `lease_release` | info | `bloc`, `leaseCount` | a lease was released |
| `staleLeaseReleased` | `bloc_lifecycle` · `lease_release_stale` | info | `bloc` | a lease on an instance the scope has since replaced was released; ignored |
| `leasedBlocGot` | `bloc_lifecycle` · `get_on_leased` | warning | `bloc` | `BlocScope.get` on a bloc registered `leased` (debug builds assert instead) |
| `featureScopeEnded` | `bloc_lifecycle` · `end_feature` | info | `scope` (the scope's name), `blocCount` | a feature scope ended its blocs |
| `allBlocsEnded` | `bloc_lifecycle` · `end_all` | info | — | `BlocScope.endAll` closed every bloc |
| `blocCloseFailed` | `bloc_close_error` | error | `bloc`, `error`, `stackTrace` | a bloc's `close()` threw; the scope still cleared its entry and rethrows |

### Errors

| kind | type · action | level | fields | when |
|---|---|---|---|---|
| `blocError` | `bloc_error` | error | `bloc`, `state`, `error`, `stackTrace` | `JuiceBloc.onError`: a use-case error, a stream-binding error, `addError` |
| `errorHandlerFailed` | `error_handler_error` | error | `bloc`, `error`, `stackTrace` | the configured `BlocErrorHandler` threw |
| `unhandledEvent` | `unhandled_event` | error | `bloc`, `event`, `error`, `stackTrace` | an event no use case handles was sent |
| `aviatorFailed` | `aviator_error` | error | `aviator`, `error`, `stackTrace` | a navigation threw |

### Stream bindings

| kind | type · action | level | fields | when |
|---|---|---|---|---|
| `streamBindingStarted` | `stream_binding` · `bind` | info | `bloc`, `key` | `bindStream` listened |
| `streamBindingDone` | `stream_binding` · `done` | info | `bloc`, `key` | the bound stream ended |
| `streamBindingRefused` | `stream_binding` · `refused` | warning (never gated) | `bloc`, `key`, `reason` (`bloc is closed` / `bloc is closing`) | `bindStream` on a closing or closed bloc returned an inert binding |
| `streamBindingSuperseded` | `stream_binding` · `refused` | info | `bloc`, `key`, `reason` (`run superseded`) | `bindStream` from a superseded restartable run returned an inert binding |
| `streamBindingError` | `stream_binding` · `error` | error | `bloc`, `key`, `error`, `stackTrace` | the stream errored and the binding has no `onError` of its own; the bloc's `onError` runs and the binding is cancelled unless `cancelOnError: false` |
| `streamBindingCallbackFailed` | `stream_binding` · `callback_error` | error | `bloc`, `key`, `callback` (`onData` / `onError` / `onDone`), `error`, `stackTrace` | a binding callback threw; the bloc's `onError` runs; an `onData` throw leaves the binding active |
| `streamBindingCancelFailed` | `stream_binding` · `cancel_error` | error | `bloc`, `key`, `site` (`at unbind` / `at close` / `at supersede` / `on error`), `error`, `stackTrace` | a subscription's cancel threw; logged, never uncaught |

### Builders and relays

| kind | type · action | level | fields | when |
|---|---|---|---|---|
| `retryScheduled` | `retry_scheduled` | info | `bloc`, `attempt`, `error` | `RetryableUseCaseBuilder` will retry after its backoff |
| `retryExhausted` | `retry_exhausted` | info | `bloc`, `attempt` (attempts made), `error` | out of attempts; the final failure is emitted |
| `retryAbandoned` | `retry_abandoned` | info | `bloc`, `attempt` | the bloc closed during a backoff |
| `eventSubscriptionInitialized` | `event_subscription` · `initialize` | info | `sourceBloc`, `sourceEvent`, `localEvent` | an `EventSubscription` subscribed to its source |
| `eventSubscriptionTriggered` | `event_subscription` · `trigger` | info | `sourceBloc`, `sourceEvent`, `localEvent` | a source event was forwarded as a local one |
| `eventSubscriptionClosed` | `event_subscription` · `close` | info | `sourceBloc`, `sourceEvent` | the subscription closed |
| `eventSubscriptionFailed` | `event_subscription` · `error` | error | `site` (`initialize` / `transform` / `stream`), `sourceBloc`, `sourceEvent`, `localEvent`, `error`, `stackTrace` | the subscription failed at that step; an `initialize` failure is also thrown to the constructor's caller |
| `relayFailed` | `relay_error` | error | `relay` (`StateRelay` / `StatusRelay`), `site` (`initialize` / `transform` / `stream`), `sourceBloc`, `destBloc`, `error`, `stackTrace` | the relay failed at that step; an `initialize` failure is also thrown |
| `leakDetectionEnabled` | `leak_detection` · `enable` | info | — | `BlocScope.enableLeakDetection` (debug builds only: it runs inside an `assert`) |

## 4. The DevTools wire

`DevtoolsJuiceLogger` posts every recorded entry as a VM extension event
`juice:<type>` whose payload is `toMap()` without `type`, plus `message` and
`level`, plus `stackTrace` when the entry has one (an `error` field crosses
as its string), every value clipped to 512 characters. Free-form `log` lines
post only when their context carries a `type`; free-form `logError` lines
always post, as `juice:<type>` when typed and `juice:error` otherwise. The
`juice_observability` DevTools extension consumes that stream.

## 5. Testing against telemetry

`juiceTest` counts `useCaseFailed`, `sequentialRunFailed` and the three
binding-error kinds into its `errors:` expectation, and fails a test on
`emissionAfterClose` or a span left open at close. For your own assertions,
a recording logger is a dozen lines:

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
`entry.toMap()` is that map — the same keys, including `streamBindings` and
`blocsEnded` — and `entry.level` that level. What changed on the wire:

- `message` is a constant per kind; the facts that used to be interpolated
  (the emission's status, a refusal's reason, the callback that threw) are
  fields.
- Two entries have their own `type` instead of sharing one: a sequential
  run's escaped failure is `sequential_run_error` (was `use_case_error`
  without an `executionId`), a failed supersede is `supersede_error` (was
  `use_case_superseded` · `error`).
- `lifecycle` is the enum's name (`leased`), not `BlocLifecycle.leased`.
- New: `sequential_run_error`, `supersede_error`, `retry_scheduled`,
  `retry_exhausted`, `relay_error`, `event_subscription` · `error`,
  `bloc_lifecycle` · `get_on_leased`; the fields `site`, `relay`, `destBloc`.
- Gone: the duplicate `use_case_error` line without an `executionId` (the
  error still reaches `bloc_error`); the second `bloc_lifecycle` · `close`
  entry the scope logged beside the bloc's own; the free-form lines the
  framework used to print (`Retrying operation`, `Retry exhausted`, the
  dispatcher's fallback warning, `BlocScope.get` on a leased bloc,
  `Closing StatefulUseCase`, `Disposing all blocs`, and
  `BlocErrorHandler`'s debug `Bloc Error:` prints) — each is now a kind, or
  nothing.

`doc/guides/upgrading-to-2.0.md` has the logger migration in full.
