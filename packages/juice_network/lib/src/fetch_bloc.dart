import 'dart:collection';

import 'package:dio/dio.dart';
import 'package:juice/juice.dart';
import 'package:juice_storage/juice_storage.dart';

import 'cache/cache_manager.dart';
import 'fetch_config.dart';
import 'fetch_events.dart';
import 'fetch_state.dart';
import 'interceptors/interceptor.dart';
import 'request/request_coalescer.dart';
import 'use_cases/cache_use_cases.dart';
import 'use_cases/cancel_use_cases.dart';
import 'use_cases/initialize_use_case.dart';
import 'use_cases/request_use_cases.dart';

/// Unified network BLoC for HTTP requests with caching and coalescing.
class FetchBloc extends JuiceBloc<FetchState> {
  /// The Dio instance for HTTP requests.
  late Dio dio;

  /// The StorageBloc for cache persistence.
  final StorageBloc storageBloc;

  /// Provider for user-specific auth identity used in cache/coalescing keys.
  ///
  /// **IMPORTANT**: If you use an AuthInterceptor to inject authentication,
  /// you MUST provide this to ensure cache/coalescing safety across users.
  final AuthIdentityProvider? authIdentityProvider;

  /// Cache manager for HTTP responses.
  late final CacheManager cacheManager;

  /// Request coalescer for deduplication.
  late final RequestCoalescer coalescer;

  /// Queue of pending requests waiting for concurrency slot.
  final Queue<Completer<void>> _requestQueue = Queue();

  /// Current number of executing requests (for concurrency limiting).
  int _executingCount = 0;

  /// Subscription to ScopeLifecycleBloc notifications.
  StreamSubscription<ScopeNotification>? _lifecycleSubscription;

  FetchBloc({
    required this.storageBloc,
    Dio? dio,
    this.authIdentityProvider,
  }) : super(
          FetchState.initial(),
          [
            // Lifecycle
            () => UseCaseBuilder(
                  typeOfEvent: InitializeFetchEvent,
                  useCaseGenerator: () => InitializeFetchUseCase(),
                ),
            () => UseCaseBuilder(
                  typeOfEvent: ResetFetchEvent,
                  useCaseGenerator: () => ResetFetchUseCase(),
                ),
            () => InlineUseCaseBuilder<FetchBloc, FetchState,
                    ReconfigureInterceptorsEvent>(
                  typeOfEvent: ReconfigureInterceptorsEvent,
                  handler: (ctx, event) async {
                    // Clear existing interceptors
                    ctx.bloc.dio.interceptors.clear();

                    // Add new interceptors (sorted by priority)
                    final sorted = event.interceptors.toList()
                      ..sort((a, b) => a.priority.compareTo(b.priority));

                    for (final interceptor in sorted) {
                      ctx.bloc.dio.interceptors
                          .add(FetchInterceptorAdapter(interceptor));
                    }
                  },
                ),

            // HTTP Methods
            () => UseCaseBuilder(
                  typeOfEvent: GetEvent,
                  useCaseGenerator: () => GetUseCase(),
                ),
            () => UseCaseBuilder(
                  typeOfEvent: PostEvent,
                  useCaseGenerator: () => PostUseCase(),
                ),
            () => UseCaseBuilder(
                  typeOfEvent: PutEvent,
                  useCaseGenerator: () => PutUseCase(),
                ),
            () => UseCaseBuilder(
                  typeOfEvent: PatchEvent,
                  useCaseGenerator: () => PatchUseCase(),
                ),
            () => UseCaseBuilder(
                  typeOfEvent: DeleteEvent,
                  useCaseGenerator: () => DeleteUseCase(),
                ),
            () => UseCaseBuilder(
                  typeOfEvent: HeadEvent,
                  useCaseGenerator: () => HeadUseCase(),
                ),

            // Cancellation
            () => UseCaseBuilder(
                  typeOfEvent: CancelRequestEvent,
                  useCaseGenerator: () => CancelRequestUseCase(),
                ),
            () => UseCaseBuilder(
                  typeOfEvent: CancelScopeEvent,
                  useCaseGenerator: () => CancelScopeUseCase(),
                ),
            () => UseCaseBuilder(
                  typeOfEvent: CancelAllEvent,
                  useCaseGenerator: () => CancelAllUseCase(),
                ),

            // Cache
            () => UseCaseBuilder(
                  typeOfEvent: InvalidateCacheEvent,
                  useCaseGenerator: () => InvalidateCacheUseCase(),
                ),
            () => UseCaseBuilder(
                  typeOfEvent: ClearCacheEvent,
                  useCaseGenerator: () => ClearCacheUseCase(),
                ),
            () => UseCaseBuilder(
                  typeOfEvent: PruneCacheEvent,
                  useCaseGenerator: () => PruneCacheUseCase(),
                ),
            () => UseCaseBuilder(
                  typeOfEvent: CleanupExpiredCacheEvent,
                  useCaseGenerator: () => CleanupExpiredCacheUseCase(),
                ),

            // Observability
            () => InlineUseCaseBuilder<FetchBloc, FetchState, ResetStatsEvent>(
                  typeOfEvent: ResetStatsEvent,
                  handler: (ctx, event) async {
                    ctx.emit.update(
                      newState: ctx.state.copyWith(stats: NetworkStats.zero()),
                      groups: {FetchGroups.statsGroup},
                    );
                  },
                ),
            () => InlineUseCaseBuilder<FetchBloc, FetchState,
                    ClearLastErrorEvent>(
                  typeOfEvent: ClearLastErrorEvent,
                  handler: (ctx, event) async {
                    ctx.emit.update(
                      newState: ctx.state.copyWith(clearLastError: true),
                      groups: {FetchGroups.error},
                    );
                  },
                ),
          ],
        ) {
    this.dio = dio ?? Dio();

    cacheManager = CacheManager(
      storageBloc: storageBloc,
      maxCacheSize: state.config.maxCacheSize,
    );

    coalescer = RequestCoalescer();

    _subscribeToLifecycle();
  }

  /// Acquire a concurrency slot, waiting if at the limit.
  ///
  /// Call [releaseConcurrencySlot] when the request completes (success or failure).
  Future<void> acquireConcurrencySlot() async {
    final maxConcurrent = state.config.maxConcurrentRequests;

    if (_executingCount < maxConcurrent) {
      _executingCount++;
      return;
    }

    // At limit - queue this request
    final completer = Completer<void>();
    _requestQueue.add(completer);
    await completer.future;
    _executingCount++;
  }

  /// Release a concurrency slot, allowing queued requests to proceed.
  void releaseConcurrencySlot() {
    _executingCount = (_executingCount - 1).clamp(0, 999999);

    // Wake up next queued request if any
    if (_requestQueue.isNotEmpty) {
      final next = _requestQueue.removeFirst();
      next.complete();
    }
  }

  void _subscribeToLifecycle() {
    if (!BlocScope.isRegistered<ScopeLifecycleBloc>()) return;

    final lifecycleBloc = BlocScope.get<ScopeLifecycleBloc>();
    _lifecycleSubscription = lifecycleBloc.notifications
        .where((n) => n is ScopeEndingNotification)
        .cast<ScopeEndingNotification>()
        .listen(_onScopeEnding);
  }

  void _onScopeEnding(ScopeEndingNotification notification) {
    send(CancelScopeEvent(scope: notification.scopeName));
    notification.barrier.add(_cancelInflightForScope(notification.scopeName));
  }

  Future<void> _cancelInflightForScope(String scope) async {
    final toCancel =
        state.activeRequests.values.where((r) => r.scope == scope).toList();

    for (final request in toCancel) {
      request.cancelToken?.cancel('Scope ended: $scope');
    }

    if (toCancel.isNotEmpty) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
  }

  @override
  Future<void> close() async {
    await _lifecycleSubscription?.cancel();
    coalescer.cancelAll('Bloc closed');

    // Cancel all queued requests
    while (_requestQueue.isNotEmpty) {
      final queued = _requestQueue.removeFirst();
      if (!queued.isCompleted) {
        queued.completeError(StateError('Bloc closed'));
      }
    }

    await super.close();
  }
}
