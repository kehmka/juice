/// Abstract base class that all bloc state classes must extend.
///
/// BlocState is intentionally minimal to provide maximum flexibility while
/// ensuring type safety in the framework. This design allows derived state
/// classes to implement their data structure however best suits their needs.
///
/// Benefits of this minimal design:
/// * Flexibility - States can be simple or complex, mutable or immutable
/// * Type Safety - Ensures proper state typing throughout the framework
/// * Future Extensibility - Additional features can be added without breaking changes
/// * No Constraints - Developers can implement state patterns that fit their needs
///
/// Example of a derived state:
/// ```dart
/// class CounterState extends BlocState {
///   final int count;
///
///   const CounterState({required this.count});
///
///   CounterState copyWith({int? count}) =>
///     CounterState(count: count ?? this.count);
/// }
/// ```
///
/// While immutable state is recommended for predictable state management,
/// this class imposes no restrictions on state mutability to support
/// different use cases and patterns.
///
/// Best practices:
/// - Prefer immutable state when possible
/// - If using mutable state, document clearly why it's needed
/// - Consider using [copyWith] pattern for state updates
/// - Be aware that widgets can potentially modify mutable state
///
/// While BlocState is minimal, derived states often implement:
/// * Immutable data structures
/// * Copyable state patterns
/// * Equatable comparisons
/// * Complex nested states
/// * Collection management
///
/// The const constructor encourages immutability as a best practice.
abstract class BlocState {
  /// Creates a constant state instance.
  ///
  /// Using const constructor encourages immutable state implementations.
  const BlocState();
}
