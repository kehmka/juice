import 'package:dio/dio.dart';

/// Base class for FetchBloc interceptors.
///
/// Interceptors run in a pipeline around network calls:
/// 1. onRequest chain (sorted by priority, lowest first)
/// 2. Network call (Dio)
/// 3. onResponse chain (reverse order) OR onError chain
///
/// Key points:
/// - Interceptors run AFTER cache lookup and coalescer check
/// - They only execute for actual network calls, not cache hits
/// - onRequest runs in priority order (lowest first)
/// - onResponse/onError run in reverse order (highest priority last)
abstract class FetchInterceptor {
  /// Called before request is sent.
  ///
  /// Return modified options to continue, or throw to abort.
  /// Throwing goes to onError chain.
  Future<RequestOptions> onRequest(RequestOptions options) async => options;

  /// Called after successful response.
  ///
  /// Return modified response to continue, or throw to convert to error.
  Future<Response<dynamic>> onResponse(Response<dynamic> response) async =>
      response;

  /// Called on error.
  ///
  /// Return modified error to propagate, or return Response to recover.
  /// Returning a Response converts the error to success.
  Future<dynamic> onError(DioException error) async => error;

  /// Priority determines execution order.
  ///
  /// Lower values run first for onRequest.
  /// Higher values run last for onResponse/onError (reverse order).
  int get priority => 0;
}

/// Recommended priority constants.
abstract class InterceptorPriority {
  /// Logging - first to see raw request.
  static const logging = 0;

  /// Authentication - add auth headers early.
  static const auth = 10;

  /// Token refresh - handle 401 before retry.
  static const refreshToken = 15;

  /// Retry - wrap request for retry logic.
  static const retry = 20;

  /// ETag - add conditional headers.
  static const etag = 30;

  /// Metrics - last to capture full timing.
  static const metrics = 100;
}

/// Adapter to convert FetchInterceptor to Dio Interceptor.
class FetchInterceptorAdapter extends Interceptor {
  final FetchInterceptor interceptor;

  FetchInterceptorAdapter(this.interceptor);

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    try {
      final modified = await interceptor.onRequest(options);
      handler.next(modified);
    } catch (e) {
      if (e is DioException) {
        handler.reject(e);
      } else {
        handler.reject(DioException(
          requestOptions: options,
          error: e,
          type: DioExceptionType.unknown,
        ));
      }
    }
  }

  @override
  Future<void> onResponse(
    Response<dynamic> response,
    ResponseInterceptorHandler handler,
  ) async {
    try {
      final modified = await interceptor.onResponse(response);
      handler.next(modified);
    } catch (e) {
      if (e is DioException) {
        handler.reject(e);
      } else {
        handler.reject(DioException(
          requestOptions: response.requestOptions,
          response: response,
          error: e,
          type: DioExceptionType.unknown,
        ));
      }
    }
  }

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    try {
      final result = await interceptor.onError(err);
      if (result is Response) {
        // Recovered - convert to success
        handler.resolve(result);
      } else if (result is DioException) {
        // Propagate modified error
        handler.next(result);
      } else {
        // Propagate original error
        handler.next(err);
      }
    } catch (e) {
      if (e is DioException) {
        handler.next(e);
      } else {
        handler.next(DioException(
          requestOptions: err.requestOptions,
          error: e,
          type: DioExceptionType.unknown,
        ));
      }
    }
  }
}
