import 'package:meta/meta.dart';

/// What caused an event that a reaction sent: the run whose emission the
/// reaction observed, and how many reaction hops deep the chain now is.
///
/// Carried OFF the event, in an [Expando] keyed on it (as the dispatcher's
/// drop flag is), never as a field: `EventBase` is subclassed by every
/// application, and a base field of any public name would be shadowed
/// silently by an event that already has one. Written only when a reaction
/// sends; an event sent by anything else has no cause and is at depth zero.
///
/// Internal. Reached by `JuiceBloc.react` and the use case executor only.
@internal
final class EventCause {
  /// Creates a cause.
  const EventCause(this.executionId, this.hopDepth);

  /// The `executionId` of the run whose emission the reaction observed;
  /// null when no run made that emission (a catch-up fire at attach, a
  /// seeded state).
  final int? executionId;

  /// The number of reaction hops from the start of the chain to the event
  /// this is the cause of: 1 for an event a reaction sent off an emission
  /// that no reaction caused.
  final int hopDepth;

  static final Expando<EventCause> _of = Expando<EventCause>('juice.cause');

  /// The cause stamped on [event], or null.
  static EventCause? of(Object event) => _of[event];

  /// Stamps [cause] on [event].
  static void stamp(Object event, EventCause cause) => _of[event] = cause;

  /// The hop depth of [event]: zero for no event, or one no reaction sent.
  static int depthOf(Object? event) =>
      event == null ? 0 : (_of[event]?.hopDepth ?? 0);
}
