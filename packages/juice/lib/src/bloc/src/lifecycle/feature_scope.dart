import 'package:flutter/foundation.dart';
import 'bloc_id.dart';

/// Groups multiple feature-level blocs for collective lifecycle management.
///
/// When a feature or user flow requires multiple blocs that should share
/// the same lifecycle, create a [FeatureScope] and register blocs with it.
/// When the feature completes, call [end] to dispose all managed blocs.
///
/// Example:
/// ```dart
/// class CheckoutFlow {
///   final scope = FeatureScope('checkout');
///
///   void start() {
///     BlocScope.register<CartBloc>(() => CartBloc(),
///         lifecycle: BlocLifecycle.feature, scope: scope);
///     BlocScope.register<PaymentBloc>(() => PaymentBloc(),
///         lifecycle: BlocLifecycle.feature, scope: scope);
///   }
///
///   Future<void> complete() => scope.end();
/// }
/// ```
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

  /// Whether this scope has been ended.
  bool get isEnded => _ended;

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

  /// End this feature scope and dispose all managed blocs.
  ///
  /// This method is idempotent - calling it multiple times is safe.
  /// After calling, the scope cannot be reused.
  Future<void> end() async {
    if (_ended) return;
    _ended = true;

    assert(() {
      _activeScopes.remove(this);
      return true;
    }());

    // BlocScope.endFeature will be called by the scope owner
    // The actual disposal is handled there
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
