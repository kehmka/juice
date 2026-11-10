import 'package:meta/meta.dart';

import 'bloc_event.dart';
import 'bloc_scope.dart';
import 'bloc_state.dart';
import 'juice_bloc.dart';
import 'lifecycle/lifecycle.dart';

/// What a [Reaction] does with the state its source is ALREADY in when the
/// reaction attaches. Required on `becomes` and `changes`: there is no
/// default, because either answer is wrong somewhere.
enum AtAttach {
  /// The state at attach does not count. The reaction fires on the next
  /// change it is looking for, and not before.
  skip,

  /// The state at attach counts: `becomes` fires if its predicate holds
  /// now, `changes` fires once with the current state. Sent like any other
  /// hop, a microtask after the attach.
  catchUp,
}

enum _Form { becomes, changes, edge }

/// One bloc reacting to another's state: when the source's state does what
/// this describes, the destination is sent an event.
///
/// A reaction is attached with `JuiceBloc.react` on the DESTINATION, which
/// owns it — it is closed with the destination like a `bindStream` binding.
/// It sees state and nothing else: every emission of the source, of every
/// status kind, is judged by its `oldState` and `state`; the status kind,
/// the event and the rebuild groups are never shown. The outcome of an
/// operation belongs to its caller, through a typed result
/// (`sendForResult`), not to a reaction.
///
/// ```dart
/// class NotificationsBloc extends JuiceBloc<NotificationsState> {
///   NotificationsBloc() : super(NotificationsState.initial, [/* … */]) {
///     react(Reaction<PermissionsBloc, PermissionsState>.changes(
///       (s) => s.statusOf(JuicePermission.notification),
///       send: (s) => SetPermissionStatusEvent(
///           s.statusOf(JuicePermission.notification) ==
///               PermissionStatus.granted),
///       atAttach: AtAttach.catchUp,
///     ));
///   }
/// }
/// ```
///
/// Three forms:
/// - [Reaction.becomes] — a predicate went from false to true;
/// - [Reaction.changes] — a selected value is no longer `==` to what it was;
/// - [Reaction.edge] — any edge you can state over `oldState` and `state`.
///
/// Every form judges ONE emission, old state against new: a reaction keeps
/// no memory of its own. A change the source made before the reaction
/// attached is not seen ([AtAttach] decides what the state at attach means).
///
/// The source is the instance passed as `source:`, or — without one — the
/// `TBloc` registered in `BlocScope` (in `scope:`, when given). A reaction
/// holds no lease on its source and never keeps it alive: when the source
/// closes, the reaction ends.
///
/// `send` builds the event from the state the reaction fired on. It runs a
/// microtask after the emission, never inside the emitting use case.
final class Reaction<TBloc extends JuiceBloc<TState>,
    TState extends BlocState> {
  /// Fires when [predicate] is true for the new state and was false for the
  /// old one.
  Reaction.becomes(
    bool Function(TState state) predicate, {
    this.source,
    this.scope,
    required this.send,
    required AtAttach this.atAttach,
  })  : _form = _Form.becomes,
        _predicate = predicate,
        _select = null,
        _edge = null {
    _checkSource();
  }

  /// Fires when the value [select] reads from the new state is not `==` to
  /// the value it reads from the old one.
  Reaction.changes(
    Object? Function(TState state) select, {
    this.source,
    this.scope,
    required this.send,
    required AtAttach this.atAttach,
  })  : _form = _Form.changes,
        _predicate = null,
        _select = select,
        _edge = null {
    _checkSource();
  }

  /// Fires when [edge] returns true for an emission's old and new state.
  /// It has no meaning at attach — there is no old state to compare — so it
  /// takes no [AtAttach] and never fires then.
  Reaction.edge(
    bool Function(TState oldState, TState state) edge, {
    this.source,
    this.scope,
    required this.send,
  })  : _form = _Form.edge,
        atAttach = null,
        _predicate = null,
        _select = null,
        _edge = edge {
    _checkSource();
  }

  /// The longest chain of reactions the framework will run: an event a
  /// reaction sends is one hop deeper than the event behind the emission it
  /// observed, and a hop past this is refused and recorded as an error. A
  /// constant, not a setting.
  static const int maxHops = 8;

  /// The source instance, when the reaction was given one.
  final TBloc? source;

  /// The `BlocScope` scope the source type is resolved in, when the
  /// reaction was given no instance.
  final Object? scope;

  /// Builds the event to send from the state the reaction fired on.
  final EventBase Function(TState state) send;

  /// What the state at attach means; null for [Reaction.edge].
  final AtAttach? atAttach;

  final _Form _form;
  final bool Function(TState state)? _predicate;
  final Object? Function(TState state)? _select;
  final bool Function(TState oldState, TState state)? _edge;

  void _checkSource() {
    if (source != null && scope != null) {
      throw ArgumentError(
          'Reaction: pass source: (an instance) or scope: (where to resolve '
          '$TBloc), not both');
    }
  }

  /// The form's name, as telemetry records it: `becomes`, `changes` or
  /// `edge`.
  @internal
  String get form => _form.name;

  /// The name of the callback that judges an emission, for a failure's
  /// `site`: `predicate`, `select` or `edge`.
  @internal
  String get judgeSite => switch (_form) {
        _Form.becomes => 'predicate',
        _Form.changes => 'select',
        _Form.edge => 'edge',
      };

  /// Whether an emission from [oldState] to [state] fires this reaction.
  /// Runs the caller's callback: it may throw.
  @internal
  bool fires(TState oldState, TState state) => switch (_form) {
        _Form.becomes => _predicate!(state) && !_predicate(oldState),
        _Form.changes => _select!(state) != _select(oldState),
        _Form.edge => _edge!(oldState, state),
      };

  /// Whether the state the source is in at attach fires this reaction
  /// (asked only under [AtAttach.catchUp]). Runs the caller's callback: it
  /// may throw.
  @internal
  bool firesAtAttach(TState state) => switch (_form) {
        _Form.becomes => _predicate!(state),
        _Form.changes => true,
        _Form.edge => false,
      };

  /// The source this reaction observes: the instance it was given, or the
  /// registered [TBloc]. Throws [StateError] for an unregistered type and
  /// for a `leased` one — a reaction holds no lease, so it cannot be what
  /// creates or keeps a leased bloc; such a source is passed as an
  /// instance, by the code that holds its lease.
  @internal
  TBloc resolveSource() {
    final given = source;
    if (given != null) return given;
    final lifecycle = BlocScope.diagnostics<TBloc>(scope: scope)?.lifecycle;
    if (lifecycle == BlocLifecycle.leased) {
      throw StateError(
          'Reaction: $TBloc is a leased bloc and cannot be resolved by type '
          '— a reaction holds no lease on its source. Pass the instance '
          '(source:) from the code that holds its lease.');
    }
    return BlocScope.get<TBloc>(scope: scope);
  }
}

/// A reaction attached to a bloc — what `JuiceBloc.react` returns; never
/// constructed directly.
///
/// The destination owns it: it ends when the destination closes, when the
/// source closes, or at [cancel]. Nothing is sent after it ends — a hop
/// already decided but not yet sent is discarded.
final class ReactionBinding {
  ReactionBinding._(this._onEnd);

  final void Function() _onEnd;
  bool _active = true;

  /// False once the reaction ended, for any reason.
  bool get isActive => _active;

  /// Detach the reaction. Idempotent.
  void cancel() {
    if (!_active) return;
    _active = false;
    _onEnd();
  }

  /// Framework-internal: the binding `JuiceBloc.react` hands out. [onEnd]
  /// runs once, when the binding ends.
  @internal
  static ReactionBinding create(void Function() onEnd) =>
      ReactionBinding._(onEnd);
}
