import 'package:juice/juice.dart';

import 'lifecycle_provider.dart';

/// Rebuild groups emitted by [LifecycleBloc].
abstract final class LifecycleGroups {
  /// Lifecycle phase changed.
  static const state = 'lifecycle:state';

  static const all = {state};
}

/// Immutable app-lifecycle state.
class LifecycleState extends BlocState {
  /// Current lifecycle phase.
  final AppLifecycle lifecycle;

  /// The phase before the current one (null before the first transition).
  final AppLifecycle? previous;

  /// When the phase last changed.
  final DateTime? lastChangedAt;

  const LifecycleState({
    this.lifecycle = AppLifecycle.resumed,
    this.previous,
    this.lastChangedAt,
  });

  static const initial = LifecycleState();

  /// Visible and interactive.
  bool get isForeground => lifecycle == AppLifecycle.resumed;

  /// Not visible (paused or hidden).
  bool get isBackground =>
      lifecycle == AppLifecycle.paused || lifecycle == AppLifecycle.hidden;

  /// Just came back to the foreground from a backgrounded/inactive phase.
  ///
  /// Useful for "re-check on resume" consumers (e.g. re-reading permissions).
  bool get resumedFromBackground =>
      lifecycle == AppLifecycle.resumed &&
      (previous == AppLifecycle.paused ||
          previous == AppLifecycle.hidden ||
          previous == AppLifecycle.inactive);

  LifecycleState copyWith({
    AppLifecycle? lifecycle,
    AppLifecycle? previous,
    DateTime? lastChangedAt,
  }) {
    return LifecycleState(
      lifecycle: lifecycle ?? this.lifecycle,
      previous: previous ?? this.previous,
      lastChangedAt: lastChangedAt ?? this.lastChangedAt,
    );
  }

  @override
  String toString() => 'LifecycleState($lifecycle, from: $previous)';
}
