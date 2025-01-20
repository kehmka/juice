import 'dart:async';
import '../../../bloc.dart';

// Function that creates a new UseCase instance
typedef UseCaseGenerator = UseCase Function();

// Function that creates a new UseCaseBuilder instance
typedef UseCaseBuilderGenerator = UseCaseBuilderBase Function();

// Function that creates an initial event for the use case
typedef UseCaseEventBuilder = EventBase Function();

// Function that creates an event based on current stream status
typedef BlocUseCaseEventBuilder = EventBase Function(StreamStatus ss);

/// Base class for building use cases that handle events in the bloc pattern
abstract class UseCaseBuilderBase {
  UseCaseBuilderBase();

  // The type of event this use case handles
  Type get eventType;

  // Optional builder for creating an initial event when the bloc starts
  UseCaseEventBuilder? get initialEventBuilder;

  // Creates the use case instance that will handle events
  UseCaseGenerator get generator;

  // Cleanup method called when the use case is disposed
  Future<void> close() async {}
}

/// Concrete implementation of UseCaseBuilderBase for creating use cases
class UseCaseBuilder implements UseCaseBuilderBase {
  UseCaseBuilder({
    required this.typeOfEvent, // Type of event this use case handles
    required this.useCaseGenerator, // Function to create the use case instance
    UseCaseEventBuilder? initialEventBuilder, // Optional initial event builder
  }) : _initialEventBuilder = initialEventBuilder;

  // Store the event type this use case handles
  final Type typeOfEvent;

  // Function that creates the use case instance
  final UseCaseGenerator useCaseGenerator;

  // Private storage for optional initial event builder
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
