/// How same-type events are processed relative to one another.
///
/// Juice dispatches each event independently, so without a policy two events of
/// the same type can interleave at every `await` inside a use case (the
/// "read state before an await, write a stale value after" race). Declare a
/// mode per event on its `UseCaseBuilder` to control this.
enum EventConcurrency {
  /// Default — same-type use cases may run concurrently (interleave at awaits).
  /// Use for genuinely independent events; follow the read-at-emit discipline.
  concurrent,

  /// Same-type events queue and run **one at a time, in order**; each use case
  /// completes (including its awaits) before the next starts. Eliminates the
  /// read-before-await race for that event type.
  sequential,

  /// A same-type event arriving **while one is already running is dropped**.
  /// Replaces hand-rolled "busy" guard flags for exclusive flows.
  droppable,

  // restartable — planned (1.6): cancel the in-flight run and start the new one.
}
