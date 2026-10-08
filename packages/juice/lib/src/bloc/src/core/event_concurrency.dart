/// How same-type events are processed relative to one another.
///
/// Juice dispatches each event independently, so without a policy two events of
/// the same type can interleave at every `await` inside a use case (the
/// "read state before an await, write a stale value after" race). Every
/// builder DECLARES its mode (`concurrency:` is required since juice 2.0.0;
/// before that it defaulted to [concurrent]) — a mode is a decision, and the
/// compiler now asks for it.
enum EventConcurrency {
  /// Same-type use cases may run concurrently (interleave at awaits). Use for
  /// genuinely independent events; follow the read-at-emit discipline. (The
  /// implicit default before 2.0.0.)
  concurrent,

  /// Same-type events queue and run **one at a time, in order**; each use case
  /// completes (including its awaits) before the next starts. Eliminates the
  /// read-before-await race for that event type.
  sequential,

  /// A same-type event arriving **while one is already running is dropped**.
  /// Replaces hand-rolled "busy" guard flags for exclusive flows.
  droppable,

  /// A same-type event arriving **while one is running supersedes it** and
  /// starts immediately (juice ≥ 2.0.0): typeahead, search, filter, select —
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
