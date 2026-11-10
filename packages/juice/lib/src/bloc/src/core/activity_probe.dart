import 'package:meta/meta.dart';

/// One piece of framework work a test flow waits for: a send that has not
/// finished processing, or a reaction hop decided but not yet sent.
@internal
final class JuiceWork {
  /// [event] sent to [bloc], until its processing is over — the time it
  /// waits in a `sequential` queue included.
  JuiceWork.send(this.bloc, this.event)
      : kind = 'send',
        source = null;

  /// A reaction of [bloc] to [source] fired; its event is not sent yet.
  JuiceWork.hop(String this.source, this.bloc)
      : kind = 'hop',
        event = null;

  /// `send` or `hop`.
  final String kind;

  /// The bloc doing the work: the one sent to, or a hop's destination.
  final String bloc;

  /// A send's event type name.
  final String? event;

  /// A hop's source bloc.
  final String? source;

  @override
  String toString() =>
      kind == 'send' ? 'send $event to $bloc' : 'hop $source → $bloc';
}

/// What the framework tells a test flow (`juiceFlowTest`) so it knows when
/// every bloc in the process is idle. Telemetry cannot say: an event queued
/// behind another `sequential` one has no span yet.
///
/// [current] is null outside a flow, and the framework then does nothing
/// but read it: one null check per send.
@internal
abstract interface class JuiceActivityProbe {
  /// The running flow's probe; null outside a flow.
  static JuiceActivityProbe? current;

  /// [work] began.
  void began(JuiceWork work);

  /// [work] is over, however it ended.
  void ended(JuiceWork work);
}
