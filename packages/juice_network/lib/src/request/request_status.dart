import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import 'request_key.dart';

/// Phase of a request in its lifecycle.
enum RequestPhase {
  /// Request is queued, waiting for execution.
  queued,

  /// Request is currently in flight.
  inflight,

  /// Request completed successfully.
  completed,

  /// Request failed with an error.
  failed,

  /// Request was cancelled.
  cancelled,
}

/// Status of an active or recently completed request.
@immutable
class RequestStatus {
  /// The request key.
  final RequestKey key;

  /// Current phase.
  final RequestPhase phase;

  /// Scope for grouping (cancellation, logging).
  final String? scope;

  /// Cancel token for this request.
  final CancelToken? cancelToken;

  /// When the request started.
  final DateTime startedAt;

  /// When the request completed (if applicable).
  final DateTime? completedAt;

  /// Current attempt number (for retries).
  final int attempt;

  /// Debug label for inspector/logging.
  final String? debugLabel;

  const RequestStatus({
    required this.key,
    required this.phase,
    this.scope,
    this.cancelToken,
    required this.startedAt,
    this.completedAt,
    this.attempt = 1,
    this.debugLabel,
  });

  /// Create an inflight status.
  factory RequestStatus.inflight({
    required RequestKey key,
    String? scope,
    CancelToken? cancelToken,
    String? debugLabel,
  }) {
    return RequestStatus(
      key: key,
      phase: RequestPhase.inflight,
      scope: scope,
      cancelToken: cancelToken,
      startedAt: DateTime.now(),
      debugLabel: debugLabel,
    );
  }

  /// Create a queued status.
  factory RequestStatus.queued({
    required RequestKey key,
    String? scope,
    CancelToken? cancelToken,
    String? debugLabel,
  }) {
    return RequestStatus(
      key: key,
      phase: RequestPhase.queued,
      scope: scope,
      cancelToken: cancelToken,
      startedAt: DateTime.now(),
      debugLabel: debugLabel,
    );
  }

  /// Whether the request is still active (queued or inflight).
  bool get isActive => phase == RequestPhase.queued || phase == RequestPhase.inflight;

  /// Duration since request started.
  Duration get elapsed => DateTime.now().difference(startedAt);

  /// Duration of completed request.
  Duration? get duration => completedAt?.difference(startedAt);

  /// Create a copy with updated values.
  RequestStatus copyWith({
    RequestPhase? phase,
    DateTime? completedAt,
    int? attempt,
  }) {
    return RequestStatus(
      key: key,
      phase: phase ?? this.phase,
      scope: scope,
      cancelToken: cancelToken,
      startedAt: startedAt,
      completedAt: completedAt ?? this.completedAt,
      attempt: attempt ?? this.attempt,
      debugLabel: debugLabel,
    );
  }

  /// Mark as completed.
  RequestStatus complete() {
    return copyWith(
      phase: RequestPhase.completed,
      completedAt: DateTime.now(),
    );
  }

  /// Mark as failed.
  RequestStatus fail() {
    return copyWith(
      phase: RequestPhase.failed,
      completedAt: DateTime.now(),
    );
  }

  /// Mark as cancelled.
  RequestStatus cancel() {
    return copyWith(
      phase: RequestPhase.cancelled,
      completedAt: DateTime.now(),
    );
  }

  /// Increment attempt counter for retry.
  RequestStatus retry() {
    return copyWith(attempt: attempt + 1);
  }

  @override
  String toString() => 'RequestStatus(${key.canonical}, $phase, attempt: $attempt)';
}
