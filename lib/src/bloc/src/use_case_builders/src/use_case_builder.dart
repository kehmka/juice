import '../../../bloc.dart';

/// Function that creates a new [UseCase] instance.
///
/// Used by [UseCaseBuilder] to generate use case instances when events
/// need to be processed.
typedef UseCaseGenerator = UseCase Function();

/// Function that creates a new [UseCaseBuilderBase] instance.
///
/// Used in bloc constructors to provide lazy initialization of use case builders.
typedef UseCaseBuilderGenerator = UseCaseBuilderBase Function();

/// Function that creates an initial event for a use case.
///
/// When provided to a use case builder, this event is dispatched
/// automatically when the bloc is initialized.
typedef UseCaseEventBuilder = EventBase Function();

/// Function that creates an event based on current stream status.
///
/// Useful for creating events that depend on the current state of the bloc.
typedef BlocUseCaseEventBuilder = EventBase Function(StreamStatus ss);

/// Base class for building use cases that handle events in the bloc pattern.
///
/// Use case builders encapsulate the configuration needed to create and
/// register use cases with a bloc. They define which event type triggers
/// the use case and how to create new instances.
///
/// See [UseCaseBuilder] for the standard implementation.
/// See [InlineUseCaseBuilder] for lambda-based use cases.
abstract class UseCaseBuilderBase {
  /// Creates a use case builder.
  UseCaseBuilderBase();

  /// The type of event this use case handles.
  Type get eventType;

  /// Optional builder for creating an initial event when the bloc starts.
  ///
  /// If provided, the event will be dispatched automatically after
  /// the bloc is initialized.
  UseCaseEventBuilder? get initialEventBuilder;

  /// Creates the use case instance that will handle events.
  UseCaseGenerator get generator;

  /// Cleanup method called when the use case is disposed.
  ///
  /// Override to release any resources held by the builder.
  Future<void> close() async {}
}

/// Standard implementation of [UseCaseBuilderBase] for creating use cases.
///
/// Connects an event type to a use case generator, enabling the bloc to
/// route events to the appropriate handler.
///
/// Example:
/// ```dart
/// class CounterBloc extends JuiceBloc<CounterState> {
///   CounterBloc() : super(CounterState(), [
///     () => UseCaseBuilder(
///       typeOfEvent: IncrementEvent,
///       useCaseGenerator: () => IncrementUseCase(),
///     ),
///     () => UseCaseBuilder(
///       typeOfEvent: LoadDataEvent,
///       useCaseGenerator: () => LoadDataUseCase(),
///       initialEventBuilder: () => LoadDataEvent(), // Auto-fires on init
///     ),
///   ]);
/// }
/// ```
class UseCaseBuilder implements UseCaseBuilderBase {
  /// Creates a use case builder.
  ///
  /// [typeOfEvent] - The event type this use case handles.
  /// [useCaseGenerator] - Factory function to create use case instances.
  /// [initialEventBuilder] - Optional factory for an initial event.
  UseCaseBuilder({
    required this.typeOfEvent,
    required this.useCaseGenerator,
    UseCaseEventBuilder? initialEventBuilder,
  }) : _initialEventBuilder = initialEventBuilder;

  /// The type of event this use case handles.
  final Type typeOfEvent;

  /// Function that creates the use case instance.
  final UseCaseGenerator useCaseGenerator;

  /// Private storage for optional initial event builder.
  final UseCaseEventBuilder? _initialEventBuilder;

  @override
  Type get eventType => typeOfEvent;

  @override
  UseCaseEventBuilder? get initialEventBuilder => _initialEventBuilder;

  @override
  UseCaseGenerator get generator => useCaseGenerator;

  @override
  Future<void> close() async {
    // No resources to clean up in base implementation
  }
}
