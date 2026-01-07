import '../../../bloc.dart';

/// A use case builder that maintains a single instance of a use case throughout its lifecycle.
///
/// Unlike the standard [UseCaseBuilder] which creates a new use case instance for each
/// event, StatefulUseCaseBuilder reuses the same instance until explicitly closed.
/// This is particularly useful for use cases that need to maintain state or manage
/// resources like connections, subscriptions, or caches.
///
/// Example:
/// ```dart
/// // Chat connection that maintains a single websocket instance
/// StatefulUseCaseBuilder(
///   typeOfEvent: ChatEvent,
///   useCaseGenerator: () => ChatConnectionUseCase(webSocketService),
/// )
/// ```
class StatefulUseCaseBuilder extends UseCaseBuilderBase {
  /// Creates a StatefulUseCaseBuilder.
  ///
  /// Parameters:
  /// * [typeOfEvent] - The type of event this use case handles
  /// * [useCaseGenerator] - Function that creates the use case instance
  /// * [initialEventBuilder] - Optional function to create an initial event
  StatefulUseCaseBuilder(
      {required this.typeOfEvent,
      required this.useCaseGenerator,
      UseCaseEventBuilder? initialEventBuilder})
      : _initialEventBuilder = initialEventBuilder;

  /// The type of event this use case handles
  final Type typeOfEvent;

  /// Function that creates the use case instance
  final UseCaseGenerator useCaseGenerator;

  /// Optional function to create an initial event
  final UseCaseEventBuilder? _initialEventBuilder;

  /// The single instance of the use case that is maintained
  UseCase? _instance;

  @override
  UseCaseEventBuilder? get initialEventBuilder => _initialEventBuilder;

  @override
  Type get eventType => typeOfEvent;

  /// Returns the existing use case instance or creates a new one if none exists.
  ///
  /// This ensures only one instance of the use case exists at a time.
  @override
  UseCaseGenerator get generator => () {
        _instance ??= useCaseGenerator();
        return _instance!;
      };

  /// Closes and cleans up the use case instance.
  ///
  /// This calls close() on the use case instance and clears the reference,
  /// allowing for proper resource cleanup.
  @override
  Future<void> close() async {
    JuiceLoggerConfig.logger.log(
        "Closing StatefulUseCase instance of type ${_instance.runtimeType}");
    _instance?.close();
    _instance = null;
  }
}
