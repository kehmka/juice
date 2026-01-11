import 'package:flutter/foundation.dart';
import 'bloc_id.dart';
import '../bloc_scope.dart';
import 'lifecycle_bloc.dart';
import 'scope_events.dart';

/// Groups multiple feature-level blocs for collective lifecycle management.
///
/// When a feature or user flow requires multiple blocs that should share
/// the same lifecycle, create a [FeatureScope] and register blocs with it.
/// When the feature completes, call [end] to dispose all managed blocs.
///
/// Example:
/// ```dart
/// class CheckoutFlow {
///   late final FeatureScope scope;
///
///   Future<void> start() async {
///     scope = await FeatureScope.create('checkout');
///     BlocScope.register<CartBloc>(() => CartBloc(),
///         lifecycle: BlocLifecycle.feature, scope: scope);
///     BlocScope.register<PaymentBloc>(() => PaymentBloc(),
///         lifecycle: BlocLifecycle.feature, scope: scope);
///   }
///
///   Future<void> complete() => scope.end();
/// }
/// ```
///
/// ## Reactive Lifecycle with LifecycleBloc
///
/// When [LifecycleBloc] is registered, FeatureScope provides reactive lifecycle:
///
/// ```dart
/// // Register LifecycleBloc first
/// BlocScope.register<LifecycleBloc>(() => LifecycleBloc(),
///     lifecycle: BlocLifecycle.permanent);
///
/// // Create scope - automatically registers with LifecycleBloc
/// final scope = await FeatureScope.create('checkout');
///
/// // End triggers cleanup sequence:
/// // 1. LifecycleBloc publishes ScopeEndingNotification
/// // 2. Subscribers register cleanup futures
/// // 3. CleanupBarrier awaited with timeout
/// // 4. Blocs disposed
/// await scope.end();
/// ```
///
/// Without LifecycleBloc, FeatureScope works but without reactive cleanup.
class FeatureScope {
  /// Creates a feature scope with an optional name for debugging.
  FeatureScope([this.name = 'unnamed']) : _id = _generateId() {
    assert(() {
      _activeScopes.add(this);
      return true;
    }());
  }

  /// Human-readable name for debugging purposes.
  final String name;

  /// Unique identifier for this scope instance.
  final String _id;

  /// Bloc IDs managed by this scope.
  final Set<BlocId> _managedBlocs = {};

  /// Whether this scope has been ended.
  bool _ended = false;

  /// Whether start() has been called.
  bool _started = false;

  /// Scope ID assigned by ScopeBloc (if registered).
  String? _scopeId;

  /// Cached end future for true idempotency.
  /// All calls to end() return this same future.
  Future<EndScopeResult>? _endFuture;

  /// Whether this scope has been ended.
  bool get isEnded => _ended;

  /// Whether end() has been called (but may not be complete).
  bool get isEnding => _endFuture != null;

  /// The scope ID assigned by LifecycleBloc, if started with LifecycleBloc.
  String? get scopeId => _scopeId;

  /// All bloc IDs managed by this scope.
  Set<BlocId> get managedBlocs => Set.unmodifiable(_managedBlocs);

  /// Track all active feature scopes for leak detection (debug only).
  static final Set<FeatureScope> _activeScopes = {};

  static String _generateId() =>
      DateTime.now().microsecondsSinceEpoch.toString();

  /// Track a bloc type as managed by this scope.
  ///
  /// Called automatically by [BlocScope.register] when registering
  /// a bloc with this scope.
  void track(Type type) {
    if (_ended) {
      throw StateError('FeatureScope "$name" already ended');
    }
    _managedBlocs.add(BlocId(type, this));
  }

  /// Explicitly start the scope and register with LifecycleBloc.
  ///
  /// Safe to call if LifecycleBloc is not registered - scope still works
  /// but without reactive lifecycle notifications.
  ///
  /// This method is idempotent - calling multiple times is safe.
  Future<void> start() async {
    if (_started) return;
    _started = true;

    // Graceful degradation: if LifecycleBloc not registered, scope still works
    // but without reactive lifecycle
    if (!BlocScope.isRegistered<LifecycleBloc>()) {
      return;
    }

    final lifecycleBloc = BlocScope.get<LifecycleBloc>();
    final event = StartScopeEvent(name: name, scope: this);
    lifecycleBloc.send(event);
    _scopeId = await event.result;
  }

  /// End this feature scope and dispose all managed blocs.
  ///
  /// **Idempotent:** Multiple calls return the same future/result.
  /// After calling, the scope cannot be reused.
  ///
  /// When [LifecycleBloc] is registered and scope was started:
  /// 1. LifecycleBloc publishes ScopeEndingNotification with CleanupBarrier
  /// 2. Subscribers register cleanup futures on barrier
  /// 3. Barrier awaited with timeout
  /// 4. All managed blocs disposed
  /// 5. LifecycleBloc publishes ScopeEndedNotification
  Future<EndScopeResult> end() {
    // True idempotency: return cached future if already ending
    _endFuture ??= _doEnd();
    return _endFuture!;
  }

  Future<EndScopeResult> _doEnd() async {
    if (_ended) {
      return EndScopeResult.notFound;
    }
    _ended = true;

    assert(() {
      _activeScopes.remove(this);
      return true;
    }());

    // Graceful degradation: if LifecycleBloc not registered or not started,
    // just dispose blocs directly
    if (!BlocScope.isRegistered<LifecycleBloc>() || _scopeId == null) {
      await BlocScope.endFeature(this);
      return const EndScopeResult(
        found: true,
        cleanupCompleted: true,
        cleanupFailedCount: 0,
        duration: Duration.zero,
        cleanupTaskCount: 0,
      );
    }

    // Use LifecycleBloc for reactive cleanup
    final lifecycleBloc = BlocScope.get<LifecycleBloc>();
    final event = EndScopeEvent(scopeId: _scopeId, scopeName: name);
    lifecycleBloc.send(event);
    return event.result;
  }

  /// Create a FeatureScope and start it.
  ///
  /// Convenience factory that creates and starts the scope in one call.
  /// Returns the started scope for chaining.
  static Future<FeatureScope> create(String name) async {
    final scope = FeatureScope(name);
    await scope.start();
    return scope;
  }

  /// Check for un-ended feature scopes (debug only).
  ///
  /// Call before app shutdown to detect leaked scopes.
  static void debugCheckLeaks() {
    assert(() {
      if (_activeScopes.isNotEmpty) {
        debugPrint('=== FeatureScope Leak Detection ===');
        for (final scope in _activeScopes) {
          debugPrint('LEAK: FeatureScope "${scope.name}" was never ended');
        }
        debugPrint('====================================');
      }
      return true;
    }());
  }

  /// Clear all tracked scopes.
  ///
  /// Used internally by [BlocScope.reset] and for testing.
  static void resetTracking() {
    _activeScopes.clear();
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is FeatureScope && other._id == _id);

  @override
  int get hashCode => _id.hashCode;

  @override
  String toString() => 'FeatureScope($name, $_id)';
}
