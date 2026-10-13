import 'dart:async';

import 'package:meta/meta.dart';

/// One run of a `restartable` use case (juice ≥ 2.0.0): the token the
/// dispatcher hands the run, carried in its zone for the length of the run
/// (across every `await`), so the framework can tell a superseded run from
/// the current one at any point — when it emits, when it binds a stream,
/// when it closes its telemetry span.
///
/// Internal. Reached by `BlocUseCase.isSuperseded` and `JuiceBloc` only.
@internal
class ExecutionRun {
  ExecutionRun(this.event);

  /// The event this run is executing.
  final Object event;

  /// True from the moment a newer same-type event supersedes this run.
  bool get isSuperseded => _superseded;
  bool _superseded = false;

  /// Completes when (and only if) this run is superseded.
  Future<void> get whenSuperseded => _supersededCompleter.future;
  final Completer<void> _supersededCompleter = Completer<void>();

  /// Mark superseded. Idempotent.
  void supersede() {
    if (_superseded) return;
    _superseded = true;
    _supersededCompleter.complete();
  }

  /// True once the run's use case has RETURNED — marked by the executor,
  /// synchronously, so a same-type event arriving in the microtasks before
  /// the dispatcher's `whenComplete` fires does not "supersede" a run that
  /// is already done (and cancel bindings that now belong to the bloc).
  bool get isComplete => _complete;
  bool _complete = false;

  /// Mark the use case returned. Idempotent.
  void complete() => _complete = true;

  /// The stream bindings this run created, so a supersede cancels exactly
  /// them (no scan of every binding the bloc holds). Bindings remove
  /// themselves when they end.
  final Set<Object> bindings = {};

  /// The zone key a restartable run is carried under.
  static const Symbol zoneKey = #juice.executionRun;

  /// The run the current zone belongs to, or null outside a restartable
  /// run.
  static ExecutionRun? get current => Zone.current[zoneKey] as ExecutionRun?;
}
