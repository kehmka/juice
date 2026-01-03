import '../../../bloc.dart';
import '../../bloc_scope.dart';
import '../../lifecycle/lifecycle.dart';

/// A specialized use case builder that connects two blocs, allowing events from one
/// to trigger events in another.
///
/// RelayUseCaseBuilder creates a bridge between two blocs by listening to state changes
/// in a source bloc and transforming them into events for a destination bloc. This enables
/// loosely coupled communication between different parts of your application.
///
/// IMPORTANT: When using RelayUseCaseBuilder, ensure that:
/// 1. Source bloc exists and is initialized before the relay starts
/// 2. Destination bloc exists and can handle the transformed events
/// 3. Blocs are disposed in the correct order (destination before source)
/// 4. The statusToEventTransformer handles all possible StreamStatus types appropriately
///
/// Type Parameters:
/// * [TSourceBloc] - The type of bloc to listen to for state changes
/// * [TDestBloc] - The type of bloc to send transformed events to
/// * [TSourceBlocState] - The state type of the source bloc, must match TSourceBloc's state type
class RelayUseCaseBuilder<
    TSourceBloc extends JuiceBloc<BlocState>,
    TDestBloc extends JuiceBloc<BlocState>,
    TSourceBlocState extends BlocState> implements UseCaseBuilderBase {
  /// Creates a RelayUseCaseBuilder to connect two blocs.
  ///
  /// Parameters:
  /// * [typeOfEvent] - The type of event this relay produces
  /// * [statusToEventTransformer] - Function to convert source state changes to destination events.
  ///   Should handle all StreamStatus types (Updating, Waiting, Error) appropriately.
  /// * [useCaseGenerator] - Generator for the use case that will handle the transformed events
  /// * [resolver] - Optional custom resolver for bloc instances (legacy). If not provided, uses BlocScope.
  /// * [sourceScope] - Optional scope key for resolving source bloc.
  /// * [destScope] - Optional scope key for resolving destination bloc.
  RelayUseCaseBuilder({
    required this.typeOfEvent,
    required this.statusToEventTransformer,
    required this.useCaseGenerator,
    this.sourceScope,
    this.destScope,
    BlocDependencyResolver? resolver,
  }) : _customResolver = resolver {
    Future.microtask(() {
      if (!_isInitialized) {
        _initialize();
      }
    });
  }

  /// The type of event this relay will generate
  final Type typeOfEvent;

  /// Function that transforms source bloc states into events for destination bloc.
  /// Should handle all possible StreamStatus types appropriately.
  final EventBase Function(StreamStatus<TSourceBlocState>)
      statusToEventTransformer;

  /// Generator for the use case that will handle transformed events
  final UseCaseGenerator useCaseGenerator;

  /// Optional scope key for resolving source bloc.
  final Object? sourceScope;

  /// Optional scope key for resolving destination bloc.
  final Object? destScope;

  /// Custom resolver for legacy compatibility.
  final BlocDependencyResolver? _customResolver;

  /// The source bloc whose states will be transformed
  late TSourceBloc sourceBloc;

  /// The destination bloc that will receive transformed events
  late TDestBloc destBloc;

  /// Lease on the source bloc (when using BlocScope).
  BlocLease<TSourceBloc>? _sourceLease;

  /// Lease on the destination bloc (when using BlocScope).
  BlocLease<TDestBloc>? _destLease;

  /// Subscription to the source bloc's stream
  StreamSubscription<dynamic>? _subscription;

  /// Whether the relay has been initialized
  bool _isInitialized = false;

  /// Whether the relay has been closed
  bool _isClosed = false;

  @override
  Type get eventType => typeOfEvent;

  @override
  UseCaseGenerator get generator => useCaseGenerator;

  @override
  UseCaseEventBuilder? get initialEventBuilder => null;

  /// Initializes the relay by resolving blocs and setting up the stream connection.
  ///
  /// Throws StateError if initialization fails or blocs cannot be resolved.
  void _initialize() {
    try {
      if (_customResolver != null) {
        // Legacy path: use custom resolver directly
        sourceBloc = _customResolver.resolve<TSourceBloc>();
        destBloc = _customResolver.resolve<TDestBloc>();
      } else {
        // New path: use BlocScope with leases for proper lifecycle management
        _sourceLease = BlocScope.lease<TSourceBloc>(scope: sourceScope);
        _destLease = BlocScope.lease<TDestBloc>(scope: destScope);
        sourceBloc = _sourceLease!.bloc;
        destBloc = _destLease!.bloc;
      }

      if (sourceBloc.isClosed || destBloc.isClosed) {
        throw StateError('Cannot initialize relay with closed blocs');
      }

      _setupPump();
      _isInitialized = true;
    } catch (e, stackTrace) {
      JuiceLoggerConfig.logger.logError(
          'Failed to initialize relay between ${TSourceBloc.runtimeType} and ${TDestBloc.runtimeType}',
          e,
          stackTrace);
      throw StateError('Relay initialization failed: $e');
    }
  }

  /// Sets up the connection between source and destination blocs.
  ///
  /// Listens to source bloc state changes and transforms them into events
  /// for the destination bloc. Handles errors and cleanup appropriately.
  void _setupPump() {
    _subscription = sourceBloc.stream.listen(
      (ss) async {
        if (_isClosed) return;

        try {
          if (destBloc.isClosed) {
            await close();
            return;
          }

          final event =
              statusToEventTransformer(ss as StreamStatus<TSourceBlocState>);
          destBloc.send(event);
        } catch (e, stackTrace) {
          JuiceLoggerConfig.logger.logError('Error in relay', e, stackTrace);
          await close();
        }
      },
      onError: (error, stackTrace) async {
        JuiceLoggerConfig.logger
            .logError('Stream error in relay', error, stackTrace);
        await close();
      },
      onDone: () async => await close(),
    );
  }

  /// Cleans up the relay by cancelling the subscription and marking as closed.
  ///
  /// This method is idempotent and can be called multiple times safely.
  @override
  Future<void> close() async {
    if (_isClosed) return;
    _isClosed = true;

    await _subscription?.cancel();
    _subscription = null;

    // Release the leases if we acquired them
    _sourceLease?.dispose();
    _sourceLease = null;
    _destLease?.dispose();
    _destLease = null;
  }
}

/// Example of complete relay chain with proper status handling:
/// ```dart
/// // States
/// class AuthState extends BlocState {
///   final String? userId;
///   final bool isAuthenticated;
///   AuthState({this.userId, this.isAuthenticated = false});
/// }
///
/// class ProfileState extends BlocState {
///   final String? name;
///   final bool isLoaded;
///   ProfileState({this.name, this.isLoaded = false});
/// }
///
/// // Events
/// class UpdateProfileEvent extends EventBase {
///   final String userId;
///   UpdateProfileEvent({required this.userId});
/// }
///
/// class LoadingProfileEvent extends EventBase {}
/// class ClearProfileEvent extends EventBase {}
///
/// // Relay setup with complete status handling
/// () => RelayUseCaseBuilder<AuthBloc, ProfileBloc, AuthState>(
///   typeOfEvent: UpdateProfileEvent,
///   statusToEventTransformer: (status) {
///     // Handle different status types
///     return status.when(
///       updating: (state, _, __) {
///         if (state.isAuthenticated) {
///           return UpdateProfileEvent(userId: state.userId!);
///         } else {
///           return ClearProfileEvent();
///         }
///       },
///       waiting: (state, _, __) {
///         return LoadingProfileEvent();
///       },
///       error: (state, _, __) {
///         return ClearProfileEvent();
///       },
///     );
///   },
///   useCaseGenerator: () => UpdateProfileUseCase(),
/// )
/// ```
