import 'package:logger/web.dart' show Level;

import '../../../bloc.dart';
import '../../core/type_names.dart';

/// Subscribes to specific events from another bloc and executes a local use case.
///
/// EventSubscription enables loosely-coupled bloc-to-bloc communication by
/// allowing a bloc to react to specific events emitted by another bloc,
/// without needing to know the source bloc's state structure.
///
/// Unlike [StateRelay] / [StatusRelay], which observe state changes,
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
  /// * [resolver] - Optional custom bloc resolver. If not provided, uses BlocScope.
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

  final BlocDependencyResolver? _customResolver;

  /// The source bloc to subscribe to.
  late TSourceBloc _sourceBloc;

  /// Lease on the source bloc (when using BlocScope).
  BlocLease<TSourceBloc>? _sourceLease;

  /// Subscription to the source bloc's stream.
  StreamSubscription<dynamic>? _subscription;

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

  /// Initializes the subscription. Called by JuiceBloc at registration.
  ///
  /// Synchronous: a subscription to an unregistered or closed bloc throws
  /// HERE, from the subscribing bloc's constructor, where the developer is
  /// looking — not as an uncaught error from a microtask nobody awaits.
  void initialize() {
    if (_isClosed) {
      throw StateError(
          'EventSubscription<$TSourceBloc, $TSourceEvent> is closed');
    }
    _initialize();
  }

  // ============================================================
  // UseCaseBuilderBase implementation
  // ============================================================

  @override
  Type get eventType => TLocalEvent;

  @override
  EventConcurrency get concurrency => EventConcurrency.concurrent;

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
    try {
      if (_customResolver != null) {
        _sourceBloc = _customResolver.resolve<TSourceBloc>();
      } else {
        _sourceLease = BlocScope.lease<TSourceBloc>(scope: scope);
        _sourceBloc = _sourceLease!.bloc;
      }

      if (_sourceBloc.isClosed) {
        throw StateError('Cannot subscribe to closed bloc: $TSourceBloc');
      }

      _setupSubscription();

      if (JuiceLoggerConfig.logs(Level.info)) {
        JuiceLoggerConfig.logger.record(JuiceTelemetry(
          JuiceTelemetryKind.eventSubscriptionInitialized,
          sourceBloc: typeName(TSourceBloc),
          sourceEvent: typeName(TSourceEvent),
          localEvent: typeName(TLocalEvent),
        ));
      }
    } catch (e, stackTrace) {
      _isClosed = true;
      _sourceLease?.dispose();
      _sourceLease = null;
      _recordFailure('initialize', e, stackTrace);
      rethrow;
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

          if (JuiceLoggerConfig.logs(Level.info)) {
            JuiceLoggerConfig.logger.record(JuiceTelemetry(
              JuiceTelemetryKind.eventSubscriptionTriggered,
              sourceBloc: typeName(TSourceBloc),
              sourceEvent: typeName(event.runtimeType),
              localEvent: typeName(localEvent.runtimeType),
            ));
          }

          _onEvent?.call(localEvent);
        } catch (e, stackTrace) {
          _recordFailure('transform', e, stackTrace);
        }
      },
      onError: (Object error, StackTrace stackTrace) =>
          _recordFailure('stream', error, stackTrace),
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

    if (JuiceLoggerConfig.logs(Level.info)) {
      JuiceLoggerConfig.logger.record(JuiceTelemetry(
        JuiceTelemetryKind.eventSubscriptionClosed,
        sourceBloc: typeName(TSourceBloc),
        sourceEvent: typeName(TSourceEvent),
      ));
    }
  }

  /// The one error entry this subscription records; [site] says which step
  /// failed (`initialize`, `transform`, `stream`).
  void _recordFailure(String site, Object error, StackTrace stackTrace) =>
      JuiceLoggerConfig.logger.record(JuiceTelemetry(
        JuiceTelemetryKind.eventSubscriptionFailed,
        site: site,
        sourceBloc: typeName(TSourceBloc),
        sourceEvent: typeName(TSourceEvent),
        localEvent: typeName(TLocalEvent),
        error: error,
        stackTrace: stackTrace,
      ));
}
