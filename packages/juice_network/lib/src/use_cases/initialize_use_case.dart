import 'package:dio/dio.dart';
import 'package:juice/juice.dart';

import '../fetch_bloc.dart';
import '../fetch_events.dart';
import '../fetch_state.dart';
import '../interceptors/interceptor.dart';

/// Use case to initialize FetchBloc.
///
/// Sets up Dio with configuration and interceptors.
/// Idempotent - calling twice is safe.
class InitializeFetchUseCase
    extends BlocUseCase<FetchBloc, InitializeFetchEvent> {
  @override
  Future<void> execute(InitializeFetchEvent event) async {
    // Already initialized? Skip (idempotent)
    if (bloc.state.isInitialized) {
      return;
    }

    final config = event.config;

    // Configure Dio
    bloc.dio.options = BaseOptions(
      baseUrl: config.baseUrl ?? '',
      connectTimeout: config.connectTimeout,
      receiveTimeout: config.receiveTimeout,
      sendTimeout: config.sendTimeout,
      headers: config.defaultHeaders,
      followRedirects: config.followRedirects,
      maxRedirects: config.maxRedirects,
      validateStatus: config.validateStatus
          ? (status) => status != null && status >= 200 && status < 300
          : (status) => true,
    );

    // Clear existing interceptors
    bloc.dio.interceptors.clear();

    // Add custom interceptors (sorted by priority)
    if (event.interceptors != null && event.interceptors!.isNotEmpty) {
      final sorted = event.interceptors!.toList()
        ..sort((a, b) => a.priority.compareTo(b.priority));

      for (final interceptor in sorted) {
        bloc.dio.interceptors.add(FetchInterceptorAdapter(interceptor));
      }
    }

    // Initialize cache manager
    await bloc.cacheManager.initialize();

    // Emit initialized state
    emitUpdate(
      groupsToRebuild: {FetchGroups.config},
      newState: bloc.state.copyWith(
        isInitialized: true,
        config: config,
      ),
    );
  }
}

/// Use case to reset FetchBloc to baseline.
class ResetFetchUseCase extends BlocUseCase<FetchBloc, ResetFetchEvent> {
  @override
  Future<void> execute(ResetFetchEvent event) async {
    // Cancel inflight requests
    if (event.cancelInflight) {
      bloc.coalescer.clear();
      for (final status in bloc.state.activeRequests.values) {
        status.cancelToken?.cancel('Reset requested');
      }
    }

    // Clear cache
    if (event.clearCache) {
      await bloc.cacheManager.clear();
    }

    // Build new state
    var newState = bloc.state.copyWith(
      activeRequests: event.cancelInflight ? {} : null,
      inflightCount: event.cancelInflight ? 0 : null,
      clearLastError: true,
    );

    if (event.resetStats) {
      newState = newState.copyWith(
        stats: NetworkStats.zero(),
        cacheStats: const CacheStats(),
      );
    }

    emitUpdate(
      groupsToRebuild: {
        FetchGroups.config,
        FetchGroups.cache,
        FetchGroups.statsGroup,
        FetchGroups.inflight,
      },
      newState: newState,
    );
  }
}
