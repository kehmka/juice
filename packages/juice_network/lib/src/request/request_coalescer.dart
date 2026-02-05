import 'dart:async';

import 'package:dio/dio.dart';

import 'request_key.dart';

/// Result of a coalesce operation.
class CoalesceResult {
  /// The response (either from coalescing or from the executed request).
  final Response<dynamic> response;

  /// Whether this request was coalesced with an existing inflight request.
  final bool wasCoalesced;

  CoalesceResult(this.response, {required this.wasCoalesced});
}

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

  /// Counter for coalesced requests (for stats tracking).
  int _coalescedCounter = 0;

  /// Callback when inflight status changes (for state sync).
  final void Function(String canonical, bool isInflight)? onInflightChanged;

  /// Callback when a request coalesces with an existing inflight request.
  final void Function(String canonical)? onCoalesced;

  RequestCoalescer({this.onInflightChanged, this.onCoalesced});

  /// Get and reset the coalesced counter.
  /// Used for stats tracking - call before and after a request to detect coalescing.
  int takeCoalescedCount() {
    final count = _coalescedCounter;
    _coalescedCounter = 0;
    return count;
  }

  /// Execute a request, coalescing with any existing inflight request.
  ///
  /// If a request with the same [key] is already inflight, returns its future.
  /// Otherwise, executes [execute] and shares the result with any subsequent
  /// requests for the same key.
  ///
  /// Returns a [CoalesceResult] that includes whether coalescing occurred.
  Future<CoalesceResult> coalesce(
    RequestKey key,
    Future<Response<dynamic>> Function() execute,
  ) async {
    final canonical = key.canonical;

    // Already inflight? Join existing request
    if (_inflight.containsKey(canonical)) {
      _coalescedCounter++;
      onCoalesced?.call(canonical);
      final response = await _inflight[canonical]!.future;
      return CoalesceResult(response, wasCoalesced: true);
    }

    // First caller - execute and share
    final completer = Completer<Response<dynamic>>();
    _inflight[canonical] = _InflightEntry(completer.future, key);
    onInflightChanged?.call(canonical, true);

    try {
      final response = await execute();
      completer.complete(response);
      return CoalesceResult(response, wasCoalesced: false);
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
