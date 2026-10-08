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

  /// The zone key a restartable run is carried under.
  static const Symbol zoneKey = #juice.executionRun;

  /// The run the current zone belongs to, or null outside a restartable
  /// run.
  static ExecutionRun? get current => Zone.current[zoneKey] as ExecutionRun?;
}
