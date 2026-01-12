import 'dart:async';

import 'package:dio/dio.dart';

import 'request_key.dart';

/// Entry for an inflight request.
class _InflightEntry {
  /// The future that will complete with the response.
  final Future<Response<dynamic>> future;

  /// The request key.
  final RequestKey key;

  /// When the request started.
  final DateTime startedAt;

  _InflightEntry(this.future, this.key) : startedAt = DateTime.now();
}

/// Coalesces identical inflight requests into a single network call.
///
/// When multiple callers request the same [RequestKey] while a request
/// is already in flight, they all receive the same response from the
/// single network call.
///
/// This is the authority for coalescing behavior. [FetchState.activeRequests]
/// is derived from this for observability/UI.
class RequestCoalescer {
  /// Inflight requests by canonical key.
  final Map<String, _InflightEntry> _inflight = {};

  /// Callback when inflight status changes (for state sync).
  final void Function(String canonical, bool isInflight)? onInflightChanged;

  RequestCoalescer({this.onInflightChanged});

  /// Execute a request, coalescing with any existing inflight request.
  ///
  /// If a request with the same [key] is already inflight, returns its future.
  /// Otherwise, executes [execute] and shares the result with any subsequent
  /// requests for the same key.
  Future<Response<dynamic>> coalesce(
    RequestKey key,
    Future<Response<dynamic>> Function() execute,
  ) async {
    final canonical = key.canonical;

    // Already inflight? Join existing request
    if (_inflight.containsKey(canonical)) {
      return _inflight[canonical]!.future;
    }

    // First caller - execute and share
    final completer = Completer<Response<dynamic>>();
    _inflight[canonical] = _InflightEntry(completer.future, key);
    onInflightChanged?.call(canonical, true);

    try {
      final response = await execute();
      completer.complete(response);
      return response;
    } catch (e, stackTrace) {
      completer.completeError(e, stackTrace);
      rethrow;
    } finally {
      _inflight.remove(canonical);
      onInflightChanged?.call(canonical, false);
    }
  }

  /// Check if a request is currently inflight.
  bool isInflight(RequestKey key) => _inflight.containsKey(key.canonical);

  /// Get the inflight future for a key, if any.
  Future<Response<dynamic>>? getInflight(RequestKey key) =>
      _inflight[key.canonical]?.future;

  /// Get current inflight canonical keys (for state sync).
  Set<String> get inflightKeys => _inflight.keys.toSet();

  /// Get count of inflight requests.
  int get inflightCount => _inflight.length;

  /// Cancel all inflight requests.
  ///
  /// Note: This doesn't actually cancel the underlying requests,
  /// it just clears the tracking. Use [CancelToken] for actual cancellation.
  void clear() {
    final keys = _inflight.keys.toList();
    _inflight.clear();
    for (final key in keys) {
      onInflightChanged?.call(key, false);
    }
  }

  /// Cancel all inflight requests with a reason.
  ///
  /// Logs the cancellation reason and clears tracking.
  void cancelAll(String reason) {
    clear();
  }
}
