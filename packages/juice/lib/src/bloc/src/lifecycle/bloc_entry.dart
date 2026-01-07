import '../juice_bloc.dart';
import '../bloc_state.dart';
import 'bloc_lifecycle.dart';

/// Internal entry tracking a registered bloc's state.
///
/// This is an internal implementation detail of [BlocScope].
class BlocEntry<T extends JuiceBloc<BlocState>> {
  BlocEntry({
    required this.factory,
    required this.lifecycle,
  });

  /// Factory function to create bloc instances.
  final T Function() factory;

  /// The lifecycle behavior for this bloc.
  final BlocLifecycle lifecycle;

  /// The current bloc instance, if created.
  T? instance;

  /// Number of active leases on this bloc.
  int leaseCount = 0;

  /// Future tracking an in-progress close operation.
  ///
  /// Used to prevent double-close races and to block new instance
  /// creation until the previous instance is fully closed.
  Future<void>? closingFuture;

  /// When the current instance was created.
  DateTime? createdAt;

  /// Whether the bloc is active (created and not closing).
  bool get isActive => instance != null && closingFuture == null;

  /// Whether the bloc is currently being closed.
  bool get isClosing => closingFuture != null;

  /// Whether a new instance can be created.
  bool get canCreate => instance == null && closingFuture == null;
}
