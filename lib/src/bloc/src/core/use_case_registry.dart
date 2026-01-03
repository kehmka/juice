import 'dart:async';
import '../use_case_builders/use_case_builder.dart';

/// Stores and manages use case builders.
///
/// The registry maintains a mapping from event types to their corresponding
/// use case builders. It handles registration, lookup, and cleanup.
///
/// Example:
/// ```dart
/// final registry = UseCaseRegistry();
///
/// registry.register(UseCaseBuilder(
///   typeOfEvent: IncrementEvent,
///   useCaseGenerator: () => IncrementUseCase(),
/// ));
///
/// final builder = registry.getBuilder(IncrementEvent);
/// final useCase = builder?.generator();
/// ```
class UseCaseRegistry {
  final _builders = <Type, UseCaseBuilderBase>{};

  /// Registers a use case builder for its event type.
  ///
  /// The builder's [eventType] is used as the key for later lookups.
  ///
  /// Throws [StateError] if a builder is already registered for the event type.
  void register(UseCaseBuilderBase builder) {
    final eventType = builder.eventType;
    if (_builders.containsKey(eventType)) {
      throw StateError('UseCase already registered for $eventType');
    }
    _builders[eventType] = builder;
  }

  /// Gets the builder for a specific event type.
  ///
  /// Returns null if no builder is registered for the event type.
  UseCaseBuilderBase? getBuilder(Type eventType) {
    return _builders[eventType];
  }

  /// Checks if a builder exists for the event type.
  bool hasBuilder(Type eventType) => _builders.containsKey(eventType);

  /// The number of registered builders.
  int get builderCount => _builders.length;

  /// All registered builders.
  ///
  /// Returns an unmodifiable view of the builders.
  Iterable<UseCaseBuilderBase> get builders => _builders.values;

  /// All registered event types.
  Iterable<Type> get eventTypes => _builders.keys;

  /// Closes all registered builders.
  ///
  /// This should be called when the owning bloc is closed to properly
  /// clean up any resources held by stateful use cases.
  ///
  /// After calling closeAll, the registry is cleared.
  Future<void> closeAll() async {
    await Future.wait(_builders.values.map((b) => b.close()));
    _builders.clear();
  }
}
