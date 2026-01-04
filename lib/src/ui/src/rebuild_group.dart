/// A type-safe identifier for widget rebuild groups.
///
/// Use `RebuildGroup` to define compile-time safe rebuild groups instead of
/// magic strings. This provides IDE autocomplete, typo prevention, and
/// refactoring support.
///
/// ## Defining Groups
///
/// Define groups as static constants in a dedicated class per feature:
///
/// ```dart
/// abstract class CounterGroups {
///   static const counter = RebuildGroup('counter');
///   static const display = RebuildGroup('counter:display');
///   static const buttons = RebuildGroup('counter:buttons');
/// }
/// ```
///
/// ## Using in Use Cases
///
/// Convert to string set when emitting:
///
/// ```dart
/// emitUpdate(
///   newState: newState,
///   groupsToRebuild: {CounterGroups.counter}.toStringSet(),
/// );
/// ```
///
/// ## Using in Widgets
///
/// ```dart
/// class CounterDisplay extends StatelessJuiceWidget<CounterBloc> {
///   CounterDisplay() : super(groups: {CounterGroups.display}.toStringSet());
/// }
/// ```
///
/// ## Built-in Groups
///
/// - [RebuildGroup.all] - Triggers rebuild in all participating widgets
/// - [RebuildGroup.optOut] - Widget never rebuilds from bloc events
class RebuildGroup {
  /// The string identifier for this group.
  final String name;

  /// Creates a rebuild group with the given [name].
  const RebuildGroup(this.name);

  /// Special group that triggers rebuilds in all participating widgets.
  ///
  /// Equivalent to `rebuildAlways` when used as a string.
  static const all = RebuildGroup('*');

  /// Special group that opts a widget out of all rebuilds.
  ///
  /// Equivalent to `optOutOfRebuilds` when used as a string.
  static const optOut = RebuildGroup('-');

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is RebuildGroup && name == other.name;

  @override
  int get hashCode => name.hashCode;

  @override
  String toString() => 'RebuildGroup($name)';
}

/// Extension methods for working with sets of [RebuildGroup].
extension RebuildGroupSetExtension on Set<RebuildGroup> {
  /// Converts this set of [RebuildGroup] to a set of strings.
  ///
  /// Use this when passing groups to emit methods or widget constructors:
  ///
  /// ```dart
  /// emitUpdate(groupsToRebuild: {CounterGroups.counter}.toStringSet());
  /// ```
  Set<String> toStringSet() => map((g) => g.name).toSet();
}

/// Extension to convert a single [RebuildGroup] to a string set.
extension RebuildGroupExtension on RebuildGroup {
  /// Converts this single group to a set containing just its string name.
  ///
  /// Convenience method for single-group usage:
  ///
  /// ```dart
  /// emitUpdate(groupsToRebuild: CounterGroups.counter.toSet());
  /// ```
  Set<String> toSet() => {name};
}
