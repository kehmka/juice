import '../juice_bloc.dart';
import '../bloc_state.dart';

/// Represents active usage of a bloc instance.
///
/// A lease is a reference-counted handle to a bloc. While any lease
/// is held, the bloc will not be auto-disposed (for [BlocLifecycle.leased] blocs).
///
/// Leases MUST be acquired in `initState()` and released in `dispose()`.
/// Never acquire or release leases in `build()` methods.
///
/// Example:
/// ```dart
/// class _MyWidgetState extends State<MyWidget> {
///   BlocLease<MyBloc>? _lease;
///
///   @override
///   void initState() {
///     super.initState();
///     _lease = BlocScope.lease<MyBloc>();
///   }
///
///   @override
///   void dispose() {
///     _lease?.dispose();
///     super.dispose();
///   }
/// }
/// ```
class BlocLease<T extends JuiceBloc<BlocState>> {
  /// Creates a lease with the bloc instance and release callback.
  ///
  /// **Note:** This constructor is for internal use by [BlocScope].
  /// Use [BlocScope.lease] to acquire leases.
  BlocLease(this.bloc, this._release);

  /// The bloc instance this lease provides access to.
  final T bloc;

  /// The release callback that decrements the lease count.
  final void Function() _release;

  /// Whether this lease has been released.
  bool _released = false;

  /// Whether this lease has been released.
  bool get isReleased => _released;

  /// Releases this lease.
  ///
  /// Safe to call multiple times - subsequent calls are no-ops.
  /// After releasing, the bloc may be disposed if this was the last lease.
  void dispose() {
    if (!_released) {
      _released = true;
      _release();
    }
  }
}
