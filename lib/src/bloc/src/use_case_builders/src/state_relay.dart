import '../../../bloc.dart';

/// Relays state changes from one bloc to another by transforming states into events.
///
/// `StateRelay` provides a clean way to react to state changes in a source bloc
/// and trigger events in a destination bloc. This enables loosely coupled
/// communication between different parts of your application.
///
/// For reacting to events (not state changes), use [EventSubscription] instead.
///
/// ## Simple Example
///
/// ```dart
/// // When cart state changes, update order summary
/// final relay = StateRelay<CartBloc, OrderBloc, CartState>(
///   toEvent: (state) => UpdateTotalEvent(
///     total: state.items.fold(0, (sum, item) => sum + item.price),
///   ),
/// );
/// ```
///
/// ## With Filtering
///
/// ```dart
/// // Only relay when user is authenticated
/// final relay = StateRelay<AuthBloc, ProfileBloc, AuthState>(
///   toEvent: (state) => LoadProfileEvent(userId: state.userId!),
///   when: (state) => state.isAuthenticated && state.userId != null,
/// );
/// ```
///
/// ## Lifecycle
///
/// The relay starts listening immediately upon construction. Call [close]
/// when the relay is no longer needed to clean up resources.
///
/// ```dart
/// final relay = StateRelay<SourceBloc, DestBloc, SourceState>(...);
///
/// // Later, when done:
/// await relay.close();
/// ```
class StateRelay<TSourceBloc extends JuiceBloc<TSourceState>,
    TDestBloc extends JuiceBloc<BlocState>, TSourceState extends BlocState> {
  /// Creates a StateRelay to connect two blocs via state changes.
  ///
  /// Parameters:
  /// * [toEvent] - Function to transform source state into a destination event.
  /// * [when] - Optional predicate to filter which state changes trigger relay.
  ///   If not provided, all state changes are relayed.
  /// * [sourceScope] - Optional scope key for resolving source bloc.
  /// * [destScope] - Optional scope key for resolving destination bloc.
  /// * [resolver] - Optional custom resolver (legacy). If not provided, uses BlocScope.
  StateRelay({
    required this.toEvent,
    this.when,
    this.sourceScope,
    this.destScope,
    BlocDependencyResolver? resolver,
  }) : _customResolver = resolver {
    Future.microtask(() {
      if (!_isInitialized && !_isClosed) {
        _initialize();
      }
    });
  }

  /// Function that transforms source bloc state into an event for destination bloc.
  final EventBase Function(TSourceState state) toEvent;

  /// Optional predicate to filter which state changes should be relayed.
  /// If null, all state changes are relayed.
  final bool Function(TSourceState state)? when;

  /// Optional scope key for resolving source bloc.
  final Object? sourceScope;

  /// Optional scope key for resolving destination bloc.
  final Object? destScope;

  /// Custom resolver for legacy compatibility.
  final BlocDependencyResolver? _customResolver;

  /// The source bloc whose states will be transformed.
  late TSourceBloc _sourceBloc;

  /// The destination bloc that will receive transformed events.
  late TDestBloc _destBloc;

  /// Lease on the source bloc (when using BlocScope).
  BlocLease<TSourceBloc>? _sourceLease;

  /// Lease on the destination bloc (when using BlocScope).
  BlocLease<TDestBloc>? _destLease;

  /// Subscription to the source bloc's stream.
  StreamSubscription<dynamic>? _subscription;

  /// Whether the relay has been initialized.
  bool _isInitialized = false;

  /// Whether the relay has been closed.
  bool _isClosed = false;

  /// Whether this relay has been closed.
  bool get isClosed => _isClosed;

  void _initialize() {
    if (_isClosed) return;

    try {
      if (_customResolver != null) {
        _sourceBloc = _customResolver.resolve<TSourceBloc>();
        _destBloc = _customResolver.resolve<TDestBloc>();
      } else {
        _sourceLease = BlocScope.lease<TSourceBloc>(scope: sourceScope);
        _destLease = BlocScope.lease<TDestBloc>(scope: destScope);
        _sourceBloc = _sourceLease!.bloc;
        _destBloc = _destLease!.bloc;
      }

      if (_sourceBloc.isClosed || _destBloc.isClosed) {
        throw StateError('Cannot initialize relay with closed blocs');
      }

      _setupRelay();
      _isInitialized = true;
    } catch (e, stackTrace) {
      JuiceLoggerConfig.logger.logError(
        'Failed to initialize StateRelay between $TSourceBloc and $TDestBloc',
        e,
        stackTrace,
      );
      throw StateError('StateRelay initialization failed: $e');
    }
  }

  void _setupRelay() {
    _subscription = _sourceBloc.stream.listen(
      (status) async {
        if (_isClosed) return;

        try {
          if (_destBloc.isClosed) {
            await close();
            return;
          }

          // Extract state from StreamStatus
          final state = status.state;

          // Apply filter if provided
          if (when != null && !when!(state)) {
            return;
          }

          final event = toEvent(state);
          _destBloc.send(event);
        } catch (e, stackTrace) {
          JuiceLoggerConfig.logger.logError(
            'Error in StateRelay<$TSourceBloc, $TDestBloc>',
            e,
            stackTrace,
          );
          // Don't close on transformer errors - just log and continue
        }
      },
      onError: (error, stackTrace) async {
        JuiceLoggerConfig.logger.logError(
          'Stream error in StateRelay<$TSourceBloc, $TDestBloc>',
          error,
          stackTrace,
        );
        await close();
      },
      onDone: () async => await close(),
    );
  }

  /// Closes the relay and releases all resources.
  ///
  /// This method is idempotent and can be called multiple times safely.
  Future<void> close() async {
    if (_isClosed) return;
    _isClosed = true;

    await _subscription?.cancel();
    _subscription = null;

    _sourceLease?.dispose();
    _sourceLease = null;
    _destLease?.dispose();
    _destLease = null;
  }
}

/// Relays StreamStatus changes from one bloc to another.
///
/// Similar to [StateRelay], but provides access to the full [StreamStatus]
/// including waiting, failure, and canceling states. Use this when you need
/// to react differently based on the status type.
///
/// ## Example
///
/// ```dart
/// final relay = StatusRelay<AuthBloc, ProfileBloc, AuthState>(
///   toEvent: (status) => status.when(
///     updating: (state, _, __) => state.isAuthenticated
///       ? LoadProfileEvent(userId: state.userId!)
///       : ClearProfileEvent(),
///     waiting: (_, __, ___) => ProfileLoadingEvent(),
///     failure: (_, __, ___) => ClearProfileEvent(),
///     canceling: (_, __, ___) => ClearProfileEvent(),
///   ),
/// );
/// ```
class StatusRelay<TSourceBloc extends JuiceBloc<TSourceState>,
    TDestBloc extends JuiceBloc<BlocState>, TSourceState extends BlocState> {
  /// Creates a StatusRelay to connect two blocs via StreamStatus changes.
  ///
  /// Parameters:
  /// * [toEvent] - Function to transform source StreamStatus into a destination event.
  /// * [when] - Optional predicate to filter which status changes trigger relay.
  /// * [sourceScope] - Optional scope key for resolving source bloc.
  /// * [destScope] - Optional scope key for resolving destination bloc.
  /// * [resolver] - Optional custom resolver (legacy). If not provided, uses BlocScope.
  StatusRelay({
    required this.toEvent,
    this.when,
    this.sourceScope,
    this.destScope,
    BlocDependencyResolver? resolver,
  }) : _customResolver = resolver {
    Future.microtask(() {
      if (!_isInitialized && !_isClosed) {
        _initialize();
      }
    });
  }

  /// Function that transforms source StreamStatus into an event for destination bloc.
  final EventBase Function(StreamStatus<TSourceState> status) toEvent;

  /// Optional predicate to filter which status changes should be relayed.
  final bool Function(StreamStatus<TSourceState> status)? when;

  /// Optional scope key for resolving source bloc.
  final Object? sourceScope;

  /// Optional scope key for resolving destination bloc.
  final Object? destScope;

  /// Custom resolver for legacy compatibility.
  final BlocDependencyResolver? _customResolver;

  late TSourceBloc _sourceBloc;
  late TDestBloc _destBloc;
  BlocLease<TSourceBloc>? _sourceLease;
  BlocLease<TDestBloc>? _destLease;
  StreamSubscription<dynamic>? _subscription;
  bool _isInitialized = false;
  bool _isClosed = false;

  /// Whether this relay has been closed.
  bool get isClosed => _isClosed;

  void _initialize() {
    if (_isClosed) return;

    try {
      if (_customResolver != null) {
        _sourceBloc = _customResolver.resolve<TSourceBloc>();
        _destBloc = _customResolver.resolve<TDestBloc>();
      } else {
        _sourceLease = BlocScope.lease<TSourceBloc>(scope: sourceScope);
        _destLease = BlocScope.lease<TDestBloc>(scope: destScope);
        _sourceBloc = _sourceLease!.bloc;
        _destBloc = _destLease!.bloc;
      }

      if (_sourceBloc.isClosed || _destBloc.isClosed) {
        throw StateError('Cannot initialize relay with closed blocs');
      }

      _setupRelay();
      _isInitialized = true;
    } catch (e, stackTrace) {
      JuiceLoggerConfig.logger.logError(
        'Failed to initialize StatusRelay between $TSourceBloc and $TDestBloc',
        e,
        stackTrace,
      );
      throw StateError('StatusRelay initialization failed: $e');
    }
  }

  void _setupRelay() {
    _subscription = _sourceBloc.stream.listen(
      (status) async {
        if (_isClosed) return;

        try {
          if (_destBloc.isClosed) {
            await close();
            return;
          }

          // Apply filter if provided
          if (when != null && !when!(status)) {
            return;
          }

          final event = toEvent(status);
          _destBloc.send(event);
        } catch (e, stackTrace) {
          JuiceLoggerConfig.logger.logError(
            'Error in StatusRelay<$TSourceBloc, $TDestBloc>',
            e,
            stackTrace,
          );
        }
      },
      onError: (error, stackTrace) async {
        JuiceLoggerConfig.logger.logError(
          'Stream error in StatusRelay<$TSourceBloc, $TDestBloc>',
          error,
          stackTrace,
        );
        await close();
      },
      onDone: () async => await close(),
    );
  }

  /// Closes the relay and releases all resources.
  Future<void> close() async {
    if (_isClosed) return;
    _isClosed = true;

    await _subscription?.cancel();
    _subscription = null;

    _sourceLease?.dispose();
    _sourceLease = null;
    _destLease?.dispose();
    _destLease = null;
  }
}
