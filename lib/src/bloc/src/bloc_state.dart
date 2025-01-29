/// Abstract base class that all bloc state classes must extend.
///
/// BlocState is intentionally minimal to provide maximum flexibility while
/// ensuring type safety in the framework. Concrete implementations should:
///
/// * Implement appropriate fields for their data
/// * Consider implementing a copy or clone mechanism
/// * Use immutable state when possible
/// * Document their state structure clearly
///
/// Example:
/// ```dart
/// class CounterState extends BlocState {
///   final int count;
///
///   const CounterState({required this.count});
///
///   // Optional but recommended copy method
///   CounterState withCount(int newCount) =>
///     CounterState(count: newCount);
/// }
/// ```
///
/// While immutable state is recommended for predictable state management,
/// this class imposes no restrictions to support different use cases.
abstract class BlocState {
  /// Creates a constant state instance.
  ///
  /// Using const constructor encourages immutable state implementations.
  const BlocState();
}
