import 'dart:async';

/// A stream the bloc listens to for as long as the bloc lives — or until it
/// is cancelled, replaced, or the stream ends (juice ≥ 2.0.0).
///
/// Created by `JuiceBloc.bindStream`; never constructed directly. The bloc
/// owns the subscription: every binding is cancelled at the start of the
/// bloc's `close()`, before its use cases close, and `onData` never runs
/// once the bloc is closing. That replaces the `StreamSubscription` field,
/// the `if (!isClosed)` guard and the manual cancel in `close()` that every
/// stream-reading bloc used to hand-roll.
///
/// - [cancel] stops listening. Idempotent; returns the subscription's own
///   cancel future (a provider's teardown, for callers that must bound it).
/// - [done] completes when the stream ends, errors out (with
///   `cancelOnError`), or the binding is cancelled — never with an error.
/// - [isActive] is false from the moment any of those happens.
/// - [key], when given, makes a later `bindStream` with the same key REPLACE
///   this one, and `unbind(key)` cancel it.
class StreamBinding<T> {
  StreamBinding._(this.key, this._onInactive, this.run);

  /// The replacement/unbind key, or null for an anonymous binding.
  final String? key;

  /// The `restartable` run that created this binding, or null when it was
  /// not created inside one. A superseded run's bindings are cancelled.
  final Object? run;

  final void Function(StreamBinding<T> binding) _onInactive;
  StreamSubscription<T>? _subscription;
  final Completer<void> _done = Completer<void>();
  bool _active = true;

  /// False once the stream ended, errored out, or the binding was cancelled
  /// or replaced.
  bool get isActive => _active;

  /// Completes when the binding stops, for any reason. Never errors.
  Future<void> get done => _done.future;

  /// Stop listening. Returns the subscription's cancel future, so a caller
  /// that must not block on a provider's teardown can bound or chain it.
  Future<void> cancel() {
    if (!_active) return Future<void>.value();
    final subscription = _subscription;
    _end();
    return subscription?.cancel() ?? Future<void>.value();
  }

  /// The stream ended or errored out: the binding is over, nothing to cancel.
  void _finish() {
    if (!_active) return;
    _end();
  }

  void _end() {
    _active = false;
    _subscription = null;
    _onInactive(this);
    if (!_done.isCompleted) _done.complete();
  }

  /// A binding refused because the bloc was already closing: inert from
  /// birth, [done] already complete, [isActive] false.
  static StreamBinding<T> inert<T>(String? key) {
    final b = StreamBinding<T>._(key, (_) {}, null);
    b._end();
    return b;
  }

  /// Wire a live binding to its subscription. Internal to `bindStream`.
  static void attach<T>(StreamBinding<T> b, StreamSubscription<T> s) {
    b._subscription = s;
  }

  /// Create a live binding. Internal to `bindStream`.
  static StreamBinding<T> create<T>(
    String? key,
    void Function(StreamBinding<T> binding) onInactive, {
    Object? run,
  }) =>
      StreamBinding<T>._(key, onInactive, run);

  /// Mark a binding finished (stream done / error). Internal to `bindStream`.
  static void finish<T>(StreamBinding<T> b) => b._finish();
}
