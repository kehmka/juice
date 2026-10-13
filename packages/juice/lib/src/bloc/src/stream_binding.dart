import 'dart:async';

/// A stream the bloc listens to for as long as the bloc lives — or until it
/// is cancelled, replaced, or the stream ends.
///
/// Created by `JuiceBloc.bindStream`; never constructed directly. The bloc
/// owns the subscription: every binding is cancelled at the start of the
/// bloc's `close()`, before its use cases close, and `onData` never runs
/// once the bloc is closing. No `StreamSubscription` field, no `isClosed`
/// guard, no manual cancel in `close()`.
///
/// - [cancel] stops listening. Idempotent; returns the subscription's own
///   cancel future (a provider's teardown, for callers that must bound it).
/// - [done] completes when the stream ends, errors out (with
///   `cancelOnError`), or the binding is cancelled — never with an error.
/// - [isActive] is false from the moment any of those happens.
/// - [key], when given, makes a later `bindStream` with the same key REPLACE
///   this one, and `unbind(key)` cancel it.
class StreamBinding<T> {
  StreamBinding._(this.key, this._onInactive);

  /// The replacement/unbind key, or null for an anonymous binding.
  final String? key;

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
  /// Every call returns that same future: a second caller awaits the one
  /// teardown, not a completed stand-in.
  Future<void> cancel() {
    final pending = _cancelFuture;
    if (pending != null) return pending;
    if (!_active) return Future<void>.value();
    final subscription = _subscription;
    _end();
    return _cancelFuture = subscription?.cancel() ?? Future<void>.value();
  }

  Future<void>? _cancelFuture;

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
    final b = StreamBinding<T>._(key, (_) {});
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
    void Function(StreamBinding<T> binding) onInactive,
  ) =>
      StreamBinding<T>._(key, onInactive);

  /// Mark a binding finished (stream done / error). Internal to `bindStream`.
  static void finish<T>(StreamBinding<T> b) => b._finish();
}
