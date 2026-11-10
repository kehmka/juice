import 'package:meta/meta.dart';

/// An event a bloc will send after a delay — what `JuiceBloc.sendAfter`
/// returns; never constructed directly.
///
/// The bloc owns the timer. The send is [isPending] until the delay
/// elapses and the event is sent, or until it is cancelled ([cancel], or
/// `cancelSend` with its [key]), replaced by a later `sendAfter` with the
/// same key, or discarded because the bloc closed. Nothing is sent after
/// any of those.
final class DelayedSend {
  DelayedSend._(this.key, this._onCancel);

  /// The replace/cancel key, or null for an anonymous delayed send.
  final String? key;

  final void Function(DelayedSend send)? _onCancel;
  bool _pending = true;

  /// True until the event is sent, or the send is cancelled, replaced or
  /// discarded.
  bool get isPending => _pending;

  /// Do not send the event. Idempotent; nothing happens if it was already
  /// sent.
  void cancel() {
    if (_pending) _onCancel!(this);
  }

  /// Framework-internal: the handle `sendAfter` hands out. [onCancel] runs
  /// when a still-pending send is cancelled through the handle.
  @internal
  static DelayedSend create(
          String? key, void Function(DelayedSend send) onCancel) =>
      DelayedSend._(key, onCancel);

  /// Framework-internal: the handle of a `sendAfter` refused because the
  /// bloc was closing — never pending.
  @internal
  static DelayedSend inert(String? key) =>
      DelayedSend._(key, null).._pending = false;

  /// Framework-internal: [send] is over — sent, cancelled, replaced or
  /// discarded.
  @internal
  static void end(DelayedSend send) => send._pending = false;
}
