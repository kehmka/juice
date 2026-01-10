import '../../../bloc.dart';

/// Subscribes to specific events from another bloc and executes a local use case.
///
/// EventSubscription enables loosely-coupled bloc-to-bloc communication by
/// allowing a bloc to react to specific events emitted by another bloc,
/// without needing to know the source bloc's state structure.
///
/// Unlike [RelayUseCaseBuilder] which observes all state changes,
/// EventSubscription filters for specific event types, resulting in
/// cleaner, more targeted inter-bloc communication.
///
/// The [toEvent] transformer isolates coupling - the subscribing bloc
/// only needs to know about the source event structure, not the source state.
///
/// Type Parameters:
/// * [TSourceBloc] - The bloc type to subscribe to
/// * [TSourceEvent] - The event type to listen for from the source bloc
/// * [TLocalEvent] - The local event type to transform into and execute
///
/// Example:
/// ```dart
/// class ProfileBloc extends JuiceBloc<ProfileState> {
///   ProfileBloc() : super(ProfileState(), [
///     // Subscribe to AuthBloc's LoginSuccessEvent
///     () => EventSubscription<AuthBloc, LoginSuccessEvent, LoadProfileEvent>(
///       toEvent: (e) => LoadProfileEvent(userId: e.userId),
///       useCaseGenerator: () => LoadProfileUseCase(),
///     ),
///   ], []);
/// }
/// ```
class EventSubscription<
    TSourceBloc extends JuiceBloc<BlocState>,
    TSourceEvent extends EventBase,
    TLocalEvent extends EventBase> implements UseCaseBuilderBase {
  /// Creates an EventSubscription.
  ///
  /// Parameters:
  /// * [toEvent] - Transforms the source event to a local event type.
  ///   This isolates coupling to the transformer only.
  /// * [useCaseGenerator] - Creates the use case that handles the local event.
  /// * [when] - Optional predicate to filter which source events trigger execution.
  /// * [statusTypes] - Which status types to listen for. Defaults to [UpdatingStatus] only.
  /// * [resolver] - Optional custom bloc resolver (legacy). If not provided, uses BlocScope.
  /// * [scope] - Optional scope key for resolving scoped bloc instances.
  EventSubscription({
    required this.toEvent,
    required this.useCaseGenerator,
    this.when,
    this.statusTypes = const {UpdatingStatus},
    this.scope,
    BlocDependencyResolver? resolver,
  }) : _customResolver = resolver;

  /// Transforms the source event to a local event type.
  final TLocalEvent Function(TSourceEvent sourceEvent) toEvent;

  /// Creates the use case instance that handles the local event.
  final UseCaseGenerator useCaseGenerator;

  /// Optional predicate to filter which source events trigger execution.
  final bool Function(TSourceEvent event)? when;

  /// Which status types to listen for.
  /// Defaults to {UpdatingStatus} - only successful state updates.
  final Set<Type> statusTypes;

  /// Optional scope key for resolving scoped bloc instances.
  final Object? scope;

  /// Custom resolver for legacy compatibility.
  final BlocDependencyResolver? _customResolver;

  /// The source bloc to subscribe to.
  late TSourceBloc _sourceBloc;

  /// Lease on the source bloc (when using BlocScope).
  BlocLease<TSourceBloc>? _sourceLease;

  /// Subscription to the source bloc's stream.
  StreamSubscription<dynamic>? _subscription;

  /// Whether the subscription has been initialized.
  bool _isInitialized = false;

  /// Whether the subscription has been closed.
  bool _isClosed = false;

  /// Callback to dispatch the transformed event.
  /// Set by JuiceBloc during registration.
  void Function(TLocalEvent event)? _onEvent;

  /// Sets the callback for event dispatch.
  /// Called by JuiceBloc during registration.
  void setEventHandler(void Function(TLocalEvent event) handler) {
    _onEvent = handler;
  }

  /// Initializes the subscription. Called by JuiceBloc.
  void initialize() {
    if (!_isInitialized && !_isClosed) {
      Future.microtask(() => _initialize());
    }
  }

  // ============================================================
  // UseCaseBuilderBase implementation
  // ============================================================

  @override
  Type get eventType => TLocalEvent;

  @override
  UseCaseGenerator get generator => useCaseGenerator;

  @override
  UseCaseEventBuilder? get initialEventBuilder => null;

  // ============================================================
  // EventSubscription-specific properties
  // ============================================================

  /// The source event type this subscription listens for.
  Type get sourceEventType => TSourceEvent;

  /// The source bloc type to subscribe to.
  Type get sourceBlocType => TSourceBloc;

  void _initialize() {
    // Guard against race condition: close() may have been called
    // after initialize() scheduled this microtask but before it executed
    if (_isClosed) return;

    try {
      if (_customResolver != null) {
        // Legacy path: use custom resolver directly
        _sourceBloc = _customResolver.resolve<TSourceBloc>();
      } else {
        // New path: use BlocScope with lease for proper lifecycle management
        _sourceLease = BlocScope.lease<TSourceBloc>(scope: scope);
        _sourceBloc = _sourceLease!.bloc;
      }

      if (_sourceBloc.isClosed) {
        throw StateError('Cannot subscribe to closed bloc: $TSourceBloc');
      }

      _setupSubscription();
      _isInitialized = true;

      JuiceLoggerConfig.logger.log(
        'EventSubscription initialized',
        context: {
          'type': 'event_subscription',
          'action': 'initialize',
          'sourceBloc': TSourceBloc.toString(),
          'sourceEvent': TSourceEvent.toString(),
          'localEvent': TLocalEvent.toString(),
        },
      );
    } catch (e, stackTrace) {
      JuiceLoggerConfig.logger.logError(
        'Failed to initialize EventSubscription for $TSourceBloc.$TSourceEvent',
        e,
        stackTrace,
      );
    }
  }

  void _setupSubscription() {
    _subscription = _sourceBloc.stream.listen(
      (status) {
        if (_isClosed) return;

        // Check status type using instance check (handles generics correctly)
        final isValidStatus = statusTypes.any((type) {
          if (type == UpdatingStatus) return status is UpdatingStatus;
          if (type == WaitingStatus) return status is WaitingStatus;
          if (type == FailureStatus) return status is FailureStatus;
          if (type == CancelingStatus) return status is CancelingStatus;
          return false;
        });
        if (!isValidStatus) {
          return;
        }

        // Check event type
        final event = status.event;
        if (event is! TSourceEvent) {
          return;
        }

        // Check predicate
        if (when != null && !when!(event)) {
          return;
        }

        // Transform and execute
        try {
          final localEvent = toEvent(event);

          JuiceLoggerConfig.logger.log(
            'EventSubscription triggered',
            context: {
              'type': 'event_subscription',
              'action': 'trigger',
              'sourceBloc': TSourceBloc.toString(),
              'sourceEvent': event.runtimeType.toString(),
              'localEvent': localEvent.runtimeType.toString(),
            },
          );

          _onEvent?.call(localEvent);
        } catch (e, stackTrace) {
          JuiceLoggerConfig.logger.logError(
            'Error in EventSubscription transformer',
            e,
            stackTrace,
            context: {
              'sourceBloc': TSourceBloc.toString(),
              'sourceEvent': TSourceEvent.toString(),
            },
          );
        }
      },
      onError: (error, stackTrace) {
        JuiceLoggerConfig.logger.logError(
          'Stream error in EventSubscription',
          error,
          stackTrace,
        );
      },
      onDone: () => close(),
    );
  }

  @override
  Future<void> close() async {
    if (_isClosed) return;
    _isClosed = true;

    await _subscription?.cancel();
    _subscription = null;

    // Release the lease if we acquired one
    _sourceLease?.dispose();
    _sourceLease = null;

    JuiceLoggerConfig.logger.log(
      'EventSubscription closed',
      context: {
        'type': 'event_subscription',
        'action': 'close',
        'sourceBloc': TSourceBloc.toString(),
        'sourceEvent': TSourceEvent.toString(),
      },
    );
  }
}
