import 'package:juice/juice.dart';

/// Base class for events that support cancellation.
///
/// CancellableEvent provides cancellation support for long-running operations.
/// The event maintains cancellation state that can be checked by use cases
/// during execution.
///
/// Example:
/// ```dart
/// class ProcessOrderEvent extends CancellableEvent {
///   final String orderId;
///   ProcessOrderEvent({required this.orderId});
/// }
/// ```
abstract class CancellableEvent extends EventBase {
  CancellableEvent() {
    _completer = Completer<void>();
  }

  bool _isCancelled = false;
  late final Completer<void> _completer;

  /// Whether this event has been cancelled
  bool get isCancelled => _isCancelled;

  /// Future that completes when the event is cancelled
  Future<void> get whenCancelled => _completer.future;

  /// Cancels the operation associated with this event
  void cancel() {
    if (!_isCancelled) {
      _isCancelled = true;
      if (!_completer.isCompleted) {
        _completer.complete();
      }
    }
  }

  /// Resets the cancellation state of this event
  ///
  /// This is primarily for testing and should not typically
  /// be used in production code.
  @visibleForTesting
  void reset() {
    _isCancelled = false;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CancellableEvent &&
          runtimeType == other.runtimeType &&
          _isCancelled == other._isCancelled;

  @override
  int get hashCode => Object.hash(runtimeType, _isCancelled);
}

/// Mixin that adds timeout capabilities to [CancellableEvent].
///
/// Automatically cancels the event after the specified timeout duration.
/// Also provides timing information and timeout state.
///
/// Example:
/// ```dart
/// class ProcessOrderEvent extends CancellableEvent with TimeoutSupport {
///   ProcessOrderEvent({Duration? timeout}) {
///     this.timeout = timeout;
///   }
/// }
/// ```
mixin TimeoutSupport on CancellableEvent {
  Duration? _timeout;
  DateTime? _startTime;
  Timer? _timeoutTimer;
  bool _isTimedOut = false;

  /// Sets a timeout duration for this event.
  ///
  /// When set, the event will automatically cancel after this duration.
  /// Setting to null clears any existing timeout.
  ///
  /// [value] - The duration after which the event should timeout, or null to clear
  set timeout(Duration? value) {
    // Clear any existing timeout
    _timeoutTimer?.cancel();
    _timeoutTimer = null;
    _timeout = value;
    _isTimedOut = false;

    // Set new timeout if provided
    if (value != null) {
      _startTime = DateTime.now();
      _timeoutTimer = Timer(value, () {
        if (!isCancelled) {
          _isTimedOut = true;
          cancel();
        }
      });
    }
  }

  /// Gets the current timeout duration, if any
  Duration? get timeout => _timeout;

  /// Whether this event was cancelled due to timeout
  bool get isTimedOut => _isTimedOut;

  /// The time remaining before timeout, or null if no timeout set
  Duration? get timeRemaining {
    if (_timeout == null || _startTime == null) return null;
    final elapsed = DateTime.now().difference(_startTime!);
    final remaining = _timeout! - elapsed;
    return remaining.isNegative ? Duration.zero : remaining;
  }

  /// The elapsed time since the event was created
  Duration get elapsedTime {
    return _startTime == null
        ? Duration.zero
        : DateTime.now().difference(_startTime!);
  }

  /// Cleanup timer when cancelled
  @override
  void cancel() {
    _timeoutTimer?.cancel();
    _timeoutTimer = null;
    super.cancel();
  }

  /// Reset timeout state for testing
  @visibleForTesting
  @override
  void reset() {
    _timeoutTimer?.cancel();
    _timeoutTimer = null;
    _timeout = null;
    _startTime = null;
    _isTimedOut = false;
    super.reset();
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      super == other &&
          other is TimeoutSupport &&
          _timeout == other._timeout &&
          _isTimedOut == other._isTimedOut;

  @override
  int get hashCode => Object.hash(super.hashCode, _timeout, _isTimedOut);
}

/// Example of a cancellable event with timeout support:
/// ```dart
/// class ProcessOrderEvent extends CancellableEvent with TimeoutSupport {
///   final String orderId;
///   ProcessOrderEvent({
///     required this.orderId,
///     Duration? timeout,
///   }) {
///     this.timeout = timeout;
///   }
/// }
/// ```
