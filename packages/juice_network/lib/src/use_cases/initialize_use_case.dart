import 'package:dio/dio.dart';
import 'package:juice/juice.dart';

import '../fetch_bloc.dart';
import '../fetch_events.dart';
import '../fetch_state.dart';
import '../interceptors/auth_identity_requirement.dart';
import '../interceptors/interceptor.dart';

/// Replaces the Dio interceptors with [interceptors], sorted by priority.
void _installInterceptors(FetchBloc bloc, List<FetchInterceptor> interceptors) {
  bloc.dio.interceptors.clear();

  final sorted = interceptors.toList()
    ..sort((a, b) => a.priority.compareTo(b.priority));

  for (final interceptor in sorted) {
    bloc.dio.interceptors.add(FetchInterceptorAdapter(interceptor));
  }
}

/// Use case to initialize FetchBloc.
///
/// Sets up Dio with configuration and interceptors.
/// Idempotent - calling twice is safe.
///
/// An `AuthInterceptor` on a bloc with no `authIdentityProvider` is refused:
/// the use case logs and emits a failure, and the bloc stays uninitialized
/// with Dio untouched. See [authIdentityViolation].
class InitializeFetchUseCase
    extends BlocUseCase<FetchBloc, InitializeFetchEvent> {
  @override
  Future<void> execute(InitializeFetchEvent event) async {
    // Already initialized? Skip (idempotent)
    if (bloc.state.isInitialized) {
      return;
    }

    final config = event.config;

    final violation =
        authIdentityViolation(event.interceptors, bloc.authIdentityProvider);
    if (violation != null) {
      final error = StateError(violation);
      logError(error, StackTrace.current);
      emitFailure(newState: bloc.state, error: error);
      return;
    }

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

    // Replace existing interceptors with the configured ones
    _installInterceptors(bloc, event.interceptors ?? const []);

    // Initialize cache manager. It was built before this config existed, so
    // the configured size limit is applied here.
    bloc.cacheManager.maxCacheSize = config.maxCacheSize;
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

/// Use case to replace the interceptors of a FetchBloc.
///
/// An `AuthInterceptor` on a bloc with no `authIdentityProvider` is refused:
/// the use case logs and emits a failure, and the interceptors already
/// installed stay as they are. See [authIdentityViolation].
class ReconfigureInterceptorsUseCase
    extends BlocUseCase<FetchBloc, ReconfigureInterceptorsEvent> {
  @override
  Future<void> execute(ReconfigureInterceptorsEvent event) async {
    final violation =
        authIdentityViolation(event.interceptors, bloc.authIdentityProvider);
    if (violation != null) {
      final error = StateError(violation);
      logError(error, StackTrace.current);
      emitFailure(newState: bloc.state, error: error);
      return;
    }

    _installInterceptors(bloc, event.interceptors);
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
