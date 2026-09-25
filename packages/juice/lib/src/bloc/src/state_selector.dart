import 'dart:async';

import 'package:flutter/foundation.dart' show setEquals;
import 'package:flutter/widgets.dart';

import 'bloc_state.dart';
import 'juice_bloc.dart';
import 'stream_status.dart';
import '../bloc.dart' show BlocScope;
import '../../ui/src/widget_support.dart' show denyRebuild;

/// Extension that adds state selection capabilities to JuiceBloc.
///
/// State selection observes one projection of state and emits only when that
/// projection changes. It is a LEAF optimization that lives INSIDE the rebuild
/// groups vocabulary, not beside it: pass [groups] and only emissions whose
/// `groupsToRebuild` intersect them are even considered (the same
/// [denyRebuild] filter every Juice widget uses), THEN the projected value is
/// compared. Without [groups] every emission is considered — correct, but the
/// invalidation is no longer named, so prefer naming the group.
///
/// Precondition: the selected type needs VALUE equality (`==`), exactly like
/// `emitUpdate(skipIfSame:)`. A projection to a `List` with identity `==`
/// never dedupes — use [selectWith] with `listEquals`.
///
/// Example:
/// ```dart
/// // In the status group's blast radius, only when count changes
/// bloc.select((state) => state.count, groups: {FooGroups.status}).listen(print);
/// ```
extension StateSelection<TState extends BlocState> on JuiceBloc<TState> {
  /// Returns a stream that only emits when the selected value changes.
  ///
  /// [selector] - Function that extracts the value to observe from state.
  /// [groups] - Rebuild groups to listen in. When given, an emission whose
  /// groups do not intersect these is ignored entirely (its value is not
  /// compared and does not become the new "previous"). When null, every
  /// emission is considered.
  ///
  /// The stream does NOT replay the current value — read `bloc.state` for
  /// that (the widgets seed their `initialData` from it). It emits when a
  /// considered emission's projection differs from the previous one, the
  /// first comparison being against the state at subscription time. `==`
  /// equality.
  Stream<T> select<T>(
    T Function(TState state) selector, {
    Set<String>? groups,
  }) =>
      selectWith(selector, equals: (a, b) => a == b, groups: groups);

  /// Returns a stream that only emits when the selected value changes,
  /// using a custom equality function.
  ///
  /// [selector] - Function that extracts the value to observe from state.
  /// [equals] - Custom equality function for comparing values.
  /// [groups] - See [select].
  ///
  /// Example:
  /// ```dart
  /// bloc.selectWith(
  ///   (state) => state.items,
  ///   equals: (a, b) => listEquals(a, b),
  ///   groups: {TodoGroups.list},
  /// ).listen((items) => print('Items changed: $items'));
  /// ```
  Stream<T> selectWith<T>(
    T Function(TState state) selector, {
    required bool Function(T previous, T current) equals,
    Set<String>? groups,
  }) {
    Stream<StreamStatus<TState>> source = stream;
    if (groups != null) {
      final g = groups;
      source = source.where(
          (status) => !denyRebuild(event: status.event, rebuildGroups: g));
    }

    // `previous` is PER SUBSCRIPTION, seeded from the state at the moment
    // that listener subscribes. A single closure shared by every listener
    // (1.8.0) let the first listener advance it, so a second listener on the
    // same returned stream saw "equal" and never fired. Typed `T`, not `T?`,
    // so a legitimately-null projection participates in the comparison.
    return Stream<T>.multi((controller) {
      T previous = selector(state);
      final sub = source.listen(
        (status) {
          final value = selector(status.state);
          if (equals(previous, value)) return;
          previous = value;
          controller.add(value);
        },
        onError: controller.addError,
        onDone: controller.close,
      );
      controller.onCancel = sub.cancel;
    }, isBroadcast: true);
  }
}

/// A widget that rebuilds only when a selected portion of state changes.
///
/// A leaf optimization inside the rebuild-groups vocabulary: with [groups],
/// the widget rebuilds when an emission targets one of its groups AND the
/// selected value changed — "in this group's blast radius, only if this cell
/// moved". That is the shape for a hot cell (a list row's one field, a ticker)
/// under a group that covers a whole section. Without [groups] every emission
/// is compared, which works but leaves the invalidation unnamed.
///
/// Precondition: `T` needs value equality; see [JuiceSelectorWith] for
/// collections.
///
/// Example:
/// ```dart
/// JuiceSelector<CounterBloc, CounterState, int>(
///   groups: {CounterGroups.display},
///   selector: (state) => state.count,
///   builder: (context, count) => Text('Count: $count'),
/// )
/// ```
class JuiceSelector<TBloc extends JuiceBloc<TState>, TState extends BlocState,
    T> extends StatefulWidget {
  /// Creates a JuiceSelector.
  ///
  /// [selector] extracts the value of interest from state.
  /// [builder] builds the widget with the selected value.
  /// [bloc] is optional; if not provided, looks up from BlocScope.
  const JuiceSelector({
    super.key,
    required this.selector,
    required this.builder,
    this.bloc,
    this.groups,
  });

  /// Function that extracts the value of interest from state.
  final T Function(TState state) selector;

  /// Function that builds the widget using the selected value.
  final Widget Function(BuildContext context, T value) builder;

  /// Optional bloc instance. If not provided, looks up from BlocScope.
  final TBloc? bloc;

  /// Rebuild groups to listen in. When given, only emissions targeting one of
  /// these groups are considered (then the selected value is compared). When
  /// null, every emission is considered.
  final Set<String>? groups;

  @override
  State<JuiceSelector<TBloc, TState, T>> createState() =>
      _JuiceSelectorState<TBloc, TState, T>();
}

class _JuiceSelectorState<TBloc extends JuiceBloc<TState>,
        TState extends BlocState, T>
    extends _SelectorStateBase<JuiceSelector<TBloc, TState, T>, TBloc, TState,
        T> {
  @override
  T select(TState state) => widget.selector(state);
  @override
  bool same(T previous, T current) => previous == current;
  @override
  TBloc? blocOf(JuiceSelector<TBloc, TState, T> w) => w.bloc;
  @override
  Set<String>? groupsOf(JuiceSelector<TBloc, TState, T> w) => w.groups;
  @override
  Widget buildValue(BuildContext context, T value) =>
      widget.builder(context, value);
}

/// A widget that rebuilds only when a selected portion of state changes,
/// with custom equality comparison.
///
/// Example:
/// ```dart
/// JuiceSelectorWith<TodoBloc, TodoState, List<Todo>>(
///   selector: (state) => state.completedTodos,
///   equals: (a, b) => listEquals(a, b),
///   builder: (context, todos) => TodoList(todos: todos),
/// )
/// ```
class JuiceSelectorWith<TBloc extends JuiceBloc<TState>,
    TState extends BlocState, T> extends StatefulWidget {
  /// Creates a JuiceSelectorWith.
  const JuiceSelectorWith({
    super.key,
    required this.selector,
    required this.equals,
    required this.builder,
    this.bloc,
    this.groups,
  });

  /// Function that extracts the value of interest from state.
  final T Function(TState state) selector;

  /// Custom equality function for comparing values.
  final bool Function(T previous, T current) equals;

  /// Function that builds the widget using the selected value.
  final Widget Function(BuildContext context, T value) builder;

  /// Optional bloc instance. If not provided, looks up from BlocScope.
  final TBloc? bloc;

  /// Rebuild groups to listen in. When given, only emissions targeting one of
  /// these groups are considered (then the selected value is compared). When
  /// null, every emission is considered.
  final Set<String>? groups;

  @override
  State<JuiceSelectorWith<TBloc, TState, T>> createState() =>
      _JuiceSelectorWithState<TBloc, TState, T>();
}

class _JuiceSelectorWithState<TBloc extends JuiceBloc<TState>,
        TState extends BlocState, T>
    extends _SelectorStateBase<JuiceSelectorWith<TBloc, TState, T>, TBloc,
        TState, T> {
  @override
  T select(TState state) => widget.selector(state);
  @override
  bool same(T previous, T current) => widget.equals(previous, current);
  @override
  TBloc? blocOf(JuiceSelectorWith<TBloc, TState, T> w) => w.bloc;
  @override
  Set<String>? groupsOf(JuiceSelectorWith<TBloc, TState, T> w) => w.groups;
  @override
  Widget buildValue(BuildContext context, T value) =>
      widget.builder(context, value);
}

/// Shared subscription logic for [JuiceSelector] and [JuiceSelectorWith].
///
/// Holds the DISPLAYED value and compares each considered emission against
/// it, reading the CURRENT widget's selector and equality on every emission.
/// (1.8.0 used a StreamBuilder over `bloc.select`, which kept the old bloc's
/// value after a `bloc:` swap — StreamBuilder only applies `initialData`
/// once — and kept projecting with the first build's selector closure.)
abstract class _SelectorStateBase<
    W extends StatefulWidget,
    TBloc extends JuiceBloc<TState>,
    TState extends BlocState,
    T> extends State<W> {
  T select(TState state);
  bool same(T previous, T current);
  TBloc? blocOf(W w);
  Set<String>? groupsOf(W w);
  Widget buildValue(BuildContext context, T value);

  late TBloc _bloc;
  late T _value;
  StreamSubscription<StreamStatus<TState>>? _sub;

  @override
  void initState() {
    super.initState();
    _subscribe();
  }

  @override
  void didUpdateWidget(W oldWidget) {
    super.didUpdateWidget(oldWidget);
    final bloc = blocOf(widget) ?? BlocScope.get<TBloc>();
    // Value comparison: an inline `{Group.x}` literal is a new Set every
    // parent build and must not resubscribe each time.
    if (!identical(bloc, _bloc) ||
        !setEquals(groupsOf(widget), groupsOf(oldWidget))) {
      _sub?.cancel();
      _subscribe(bloc);
    } else {
      // The selector may be a new closure over new inputs (e.g. a row id).
      _value = select(_bloc.state);
    }
  }

  void _subscribe([TBloc? bloc]) {
    _bloc = bloc ?? blocOf(widget) ?? BlocScope.get<TBloc>();
    _value = select(_bloc.state);
    final g = groupsOf(widget);
    _sub = _bloc.stream.listen((status) {
      if (g != null && denyRebuild(event: status.event, rebuildGroups: g)) {
        return;
      }
      final next = select(status.state);
      if (same(_value, next)) return;
      setState(() => _value = next);
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => buildValue(context, _value);
}
