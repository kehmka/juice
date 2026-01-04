/// Juice - A modular reactive state management library for Flutter.
///
/// Juice combines clean architecture principles with the BLoC pattern to provide
/// structured, team-friendly state management. It enforces clear separation of
/// concerns through use cases, supports reactive UI updates via streams, and
/// offers flexible bloc lifecycle management.
///
/// ## Core Concepts
///
/// - **JuiceBloc**: The state container that manages business logic through use cases
/// - **BlocState**: Immutable state objects with copyWith support
/// - **StreamStatus**: Type-safe state transitions (Updating, Waiting, Failure)
/// - **UseCases**: Encapsulated business logic handlers for events
/// - **BlocScope**: Lifecycle management for blocs (permanent, feature, leased)
///
/// ## Quick Start
///
/// ```dart
/// // Define state
/// class CounterState extends BlocState {
///   final int count;
///   CounterState({this.count = 0});
///   CounterState copyWith({int? count}) => CounterState(count: count ?? this.count);
/// }
///
/// // Define bloc
/// class CounterBloc extends JuiceBloc<CounterState> {
///   CounterBloc() : super(CounterState(), [
///     () => UseCaseBuilder(
///       typeOfEvent: IncrementEvent,
///       useCaseGenerator: () => IncrementUseCase(),
///     ),
///   ]);
/// }
///
/// // Register and use
/// BlocScope.register<CounterBloc>(() => CounterBloc(), lifecycle: BlocLifecycle.permanent);
/// final bloc = BlocScope.get<CounterBloc>();
/// ```
///
/// ## Features
///
/// - **Group-based rebuilds**: Optimize UI performance with selective widget updates
/// - **Cross-bloc communication**: StateRelay and StatusRelay for bloc-to-bloc data flow
/// - **Navigation**: Integrated Aviator system for declarative navigation
/// - **Comprehensive logging**: Built-in logging for debugging and observability
///
/// See the [documentation](https://kehmka.github.io/juice/) for detailed guides.
library juice;

export 'package:flutter/material.dart';
export 'package:logger/logger.dart';

export 'src/bloc/bloc.dart';
export 'src/ui/ui.dart';
