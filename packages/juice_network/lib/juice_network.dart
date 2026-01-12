/// Unified network BLoC for Flutter - request coalescing, caching,
/// retry, and interceptors built on the Juice framework.
///
/// ## Quick Start
///
/// ```dart
/// // Initialize
/// fetchBloc.send(InitializeFetchEvent(
///   config: FetchConfig(baseUrl: 'https://api.example.com'),
/// ));
///
/// // Make a request
/// fetchBloc.send(GetEvent(
///   url: '/users/123',
///   decode: (raw) => User.fromJson(raw),
///   cachePolicy: CachePolicy.cacheFirst,
/// ));
/// ```
///
/// ## Features
///
/// - **Request Coalescing**: Multiple requests for the same URL share one network call
/// - **Cache Policies**: networkFirst, cacheFirst, staleWhileRevalidate, etc.
/// - **Typed Errors**: NetworkError, TimeoutError, HttpError, DecodeError
/// - **Interceptors**: Auth, Retry, Logging, ETag
/// - **Scope Cancellation**: Auto-cancel requests when LifecycleBloc scopes end
library juice_network;

// Core
export 'src/fetch_bloc.dart';
export 'src/fetch_config.dart';
export 'src/fetch_events.dart';
export 'src/fetch_exceptions.dart';
export 'src/fetch_state.dart';

// Cache
export 'src/cache/cache_manager.dart';
export 'src/cache/cache_policy.dart';
export 'src/cache/wire_cache_record.dart';

// Request
export 'src/request/request_coalescer.dart';
export 'src/request/request_key.dart';
export 'src/request/request_status.dart';

// Interceptors
export 'src/interceptors/auth_interceptor.dart';
export 'src/interceptors/etag_interceptor.dart';
export 'src/interceptors/interceptor.dart';
export 'src/interceptors/logging_interceptor.dart';
export 'src/interceptors/refresh_token_interceptor.dart';
export 'src/interceptors/retry_interceptor.dart';
