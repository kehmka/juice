/// Abstract base class that all bloc state classes must extend.
///
/// BlocState is intentionally minimal to provide maximum flexibility while
/// ensuring type safety in the framework. Concrete implementations should:
///
/// - Prefer immutable state when possible
/// - If using mutable state, document clearly why it's needed
/// * Consider implementing a copy or clone mechanism
/// - Be aware that widgets can potentially modify mutable state
///
/// While BlocState is minimal, derived states often implement:
/// * Immutable data structures
/// * Copyable state patterns
/// * Equatable comparisons
/// * Complex nested states
/// * Collection management
///
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
