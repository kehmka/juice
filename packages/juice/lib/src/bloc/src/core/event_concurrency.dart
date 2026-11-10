/// How same-type events are processed relative to one another.
///
/// Juice dispatches each event independently, so without a policy two events of
/// the same type can interleave at every `await` inside a use case (the
/// "read state before an await, write a stale value after" race). Every
/// builder DECLARES its mode (`concurrency:` is required) — a mode is a
/// decision, and the compiler asks for it.
enum EventConcurrency {
  /// Same-type use cases may run concurrently (interleave at awaits). Use for
  /// genuinely independent events; follow the read-at-emit discipline.
  concurrent,

  /// Same-type events queue and run **one at a time, in order**; each use case
  /// completes (including its awaits) before the next starts. Eliminates the
  /// read-before-await race for that event type.
  sequential,

  /// A same-type event arriving **while one is already running is dropped**.
  /// Replaces hand-rolled "busy" guard flags for exclusive flows.
  droppable,

  /// A same-type event arriving **while one is already running JOINS it**:
  /// it does not run, and it is not dropped — it gets the running one's
  /// outcome. Its `send` completes when the running one's does,
  /// `sendAndWait` answers with the running one's terminal status, and
  /// `sendForResult` returns the running one's value or throws its error.
  /// One flight, however many callers: a token refresh, a permission
  /// prompt, a pull-to-refresh.
  ///
  /// Events join by type. `UseCaseBuilder`'s `joinKey:` narrows that: two
  /// events join only when their keys are equal too (two requests for the
  /// SAME permission), and events with different keys run side by side.
  ///
  /// Where `droppable` says "one at a time, and the rest did not happen",
  /// `singleflight` says "one at a time, and the rest are answered by it".
  singleflight,

  /// A same-type event arriving **while one is running supersedes it** and
  /// starts immediately: typeahead, search, filter, select —
  /// the latest input must win. Dart cannot kill the superseded run, so it
  /// is FENCED: its `emitUpdate` / `emitWaiting` / `emitFailure` /
  /// `emitCancel` / `emitEvent` / `navigate` become no-ops (each logged as
  /// `state_emission_superseded`), the stream bindings it created are
  /// cancelled, and if its event is a `CancellableEvent` it is cancelled so
  /// the run can bail early (`BlocUseCase.isSuperseded` is the check for
  /// any other event). **Side effects already performed are NOT rolled
  /// back** — restartable fences state, not the world. `sendAndWait` on a
  /// superseded event returns a `CancelingStatus` instead of timing out.
  restartable,
}
