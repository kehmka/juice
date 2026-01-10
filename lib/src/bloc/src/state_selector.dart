import 'package:flutter/widgets.dart';

import 'bloc_state.dart';
import 'stream_status.dart';
import 'juice_bloc.dart';
import '../bloc.dart' show BlocScope;

/// Extension that adds state selection capabilities to JuiceBloc.
///
/// State selection allows you to observe only parts of state, avoiding
/// unnecessary widget rebuilds when unrelated state changes.
///
/// Example:
/// ```dart
/// // Only emits when count changes
/// bloc.select((state) => state.count).listen((count) {
///   print('Count changed to $count');
/// });
///
/// // Combine multiple selectors
/// bloc.select((state) => state.user.name).listen((name) {
///   print('User name: $name');
/// });
/// ```
extension StateSelection<TState extends BlocState> on JuiceBloc<TState> {
  /// Returns a stream that only emits when the selected value changes.
  ///
  /// [selector] - Function that extracts the value to observe from state.
  ///
  /// The stream will:
  /// - Emit immediately with the current selected value
  /// - Only emit subsequent values when they differ from the previous value
  /// - Use `==` for equality comparison
  ///
  /// Example:
  /// ```dart
  /// final countStream = bloc.select((state) => state.count);
  /// countStream.listen((count) {
  ///   // Only called when count actually changes
  ///   print('New count: $count');
  /// });
  /// ```
  Stream<T> select<T>(T Function(TState state) selector) {
    T? previous;
    bool isFirst = true;

    return stream.map((status) => selector(status.state)).where((value) {
      if (isFirst) {
        isFirst = false;
        previous = value;
        return true;
      }
      if (value == previous) return false;
      previous = value;
      return true;
    });
  }

  /// Returns a stream that only emits when the selected value changes,
  /// using a custom equality function.
  ///
  /// [selector] - Function that extracts the value to observe from state.
  /// [equals] - Custom equality function for comparing values.
  ///
  /// Example:
  /// ```dart
  /// // Use deep equality for list comparison
  /// bloc.selectWith(
  ///   (state) => state.items,
  ///   equals: (a, b) => listEquals(a, b),
  /// ).listen((items) {
  ///   print('Items changed: $items');
  /// });
  /// ```
  Stream<T> selectWith<T>(
    T Function(TState state) selector, {
    required bool Function(T previous, T current) equals,
  }) {
    T? previous;
    bool isFirst = true;

    return stream.map((status) => selector(status.state)).where((value) {
      if (isFirst) {
        isFirst = false;
        previous = value;
        return true;
      }
      if (previous != null && equals(previous as T, value)) return false;
      previous = value;
      return true;
    });
  }
}

/// A widget that rebuilds only when a selected portion of state changes.
///
/// [JuiceSelector] is more efficient than rebuilding on every state change
/// when you only care about specific parts of the state.
///
/// Example:
/// ```dart
/// JuiceSelector<CounterBloc, CounterState, int>(
///   selector: (state) => state.count,
///   builder: (context, count) => Text('Count: $count'),
/// )
/// ```
///
/// For more complex selections, use [selectWith] on the bloc stream directly.
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
  });

  /// Function that extracts the value of interest from state.
  final T Function(TState state) selector;

  /// Function that builds the widget using the selected value.
  final Widget Function(BuildContext context, T value) builder;

  /// Optional bloc instance. If not provided, looks up from BlocScope.
  final TBloc? bloc;

  @override
  State<JuiceSelector<TBloc, TState, T>> createState() =>
      _JuiceSelectorState<TBloc, TState, T>();
}

class _JuiceSelectorState<
    TBloc extends JuiceBloc<TState>,
    TState extends BlocState,
    T> extends State<JuiceSelector<TBloc, TState, T>> {
  late TBloc _bloc;
  late T _selectedValue;
  late Stream<T> _selectedStream;

  @override
  void initState() {
    super.initState();
    _initBloc();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _initBloc();
  }

  @override
  void didUpdateWidget(JuiceSelector<TBloc, TState, T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.bloc != oldWidget.bloc) {
      _initBloc();
    }
  }

  void _initBloc() {
    _bloc = widget.bloc ?? BlocScope.get<TBloc>();
    _selectedValue = widget.selector(_bloc.state);
    _selectedStream = _bloc.select(widget.selector);
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<T>(
      stream: _selectedStream,
      initialData: _selectedValue,
      builder: (context, snapshot) {
        final value = snapshot.data as T;
        return widget.builder(context, value);
      },
    );
  }
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
  });

  /// Function that extracts the value of interest from state.
  final T Function(TState state) selector;

  /// Custom equality function for comparing values.
  final bool Function(T previous, T current) equals;

  /// Function that builds the widget using the selected value.
  final Widget Function(BuildContext context, T value) builder;

  /// Optional bloc instance. If not provided, looks up from BlocScope.
  final TBloc? bloc;

  @override
  State<JuiceSelectorWith<TBloc, TState, T>> createState() =>
      _JuiceSelectorWithState<TBloc, TState, T>();
}

class _JuiceSelectorWithState<
    TBloc extends JuiceBloc<TState>,
    TState extends BlocState,
    T> extends State<JuiceSelectorWith<TBloc, TState, T>> {
  late TBloc _bloc;
  late T _selectedValue;
  late Stream<T> _selectedStream;

  @override
  void initState() {
    super.initState();
    _initBloc();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _initBloc();
  }

  @override
  void didUpdateWidget(JuiceSelectorWith<TBloc, TState, T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.bloc != oldWidget.bloc) {
      _initBloc();
    }
  }

  void _initBloc() {
    _bloc = widget.bloc ?? BlocScope.get<TBloc>();
    _selectedValue = widget.selector(_bloc.state);
    _selectedStream = _bloc.selectWith(
      widget.selector,
      equals: widget.equals,
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<T>(
      stream: _selectedStream,
      initialData: _selectedValue,
      builder: (context, snapshot) {
        final value = snapshot.data as T;
        return widget.builder(context, value);
      },
    );
  }
}
