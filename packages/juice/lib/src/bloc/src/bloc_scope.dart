import 'package:flutter/foundation.dart';
import 'juice_bloc.dart';
import 'bloc_state.dart';
import 'juice_logger.dart';
import 'lifecycle/lifecycle.dart';
import 'lifecycle/leak_detector.dart';

/// Manages bloc registration, resolution, and lifecycle.
///
/// BlocScope provides lifecycle-aware management of bloc instances:
/// - **permanent**: Lives for entire app lifetime
/// - **feature**: Lives until FeatureScope ends
/// - **leased**: Lives while widgets hold leases
///
/// ## Registration
///
/// ```dart
/// // App-level blocs (registered at startup)
/// BlocScope.register<AuthBloc>(() => AuthBloc(),
///     lifecycle: BlocLifecycle.permanent);
///
/// // Feature-level blocs
/// final scope = FeatureScope('checkout');
/// BlocScope.register<CartBloc>(() => CartBloc(),
///     lifecycle: BlocLifecycle.feature, scope: scope);
///
/// // Widget-level blocs (can also be registered by widgets)
/// BlocScope.register<FormBloc>(() => FormBloc(),
///     lifecycle: BlocLifecycle.leased);
/// ```
///
/// ## Resolution
///
/// ```dart
/// // For permanent/feature blocs
/// final auth = BlocScope.get<AuthBloc>();
///
/// // For leased blocs (required)
/// final lease = BlocScope.lease<FormBloc>();
/// // ... use lease.bloc ...
/// lease.dispose(); // Release when done
/// ```
class BlocScope {
  BlocScope._();

  /// All registered bloc entries, keyed by BlocId.
  static final Map<BlocId, BlocEntry> _entries = {};

  // ============================================================
  // Leak Detection
  // ============================================================

  /// Enable leak detection for debugging.
  ///
  /// When enabled, tracks all bloc creations and lease acquisitions
  /// with stack traces for identifying memory leaks.
  ///
  /// Should be called early in app startup:
  /// ```dart
  /// void main() {
  ///   BlocScope.enableLeakDetection();
  ///   runApp(MyApp());
  /// }
  /// ```
  ///
  /// Only works in debug mode (asserts).
  static void enableLeakDetection() {
    LeakDetector.enable();
  }

  /// Check for memory leaks and print a report.
  ///
  /// Returns true if leaks were found.
  static bool checkForLeaks() {
    return LeakDetector.checkForLeaks();
  }

  // ============================================================
  // Registration
  // ============================================================

  /// Register a bloc factory with lifecycle behavior.
  ///
  /// [factory] creates new bloc instances when needed.
  /// [lifecycle] determines when the bloc is disposed.
  /// [scope] optional scope key for multiple instances of same type.
  ///
  /// Throws [StateError] if the same BlocId is already registered
  /// with a different lifecycle.
  static void register<T extends JuiceBloc<BlocState>>(
    T Function() factory, {
    BlocLifecycle lifecycle = BlocLifecycle.permanent,
    Object? scope,
  }) {
    final id = BlocId(T, scope ?? BlocId.globalScope);

    // Check for conflicting registration
    if (_entries.containsKey(id)) {
      final existing = _entries[id]!;
      if (existing.lifecycle != lifecycle) {
        throw StateError(
          'Bloc $T (scope: $scope) already registered with '
          '${existing.lifecycle}, cannot re-register with $lifecycle',
        );
      }
      // Same lifecycle - allow re-registration (idempotent)
      return;
    }

    // Track in FeatureScope if applicable
    if (scope is FeatureScope) {
      scope.track(T);
    }

    _entries[id] = BlocEntry<T>(
      factory: factory,
      lifecycle: lifecycle,
    );

    JuiceLoggerConfig.logger.log('Bloc registered', context: {
      'type': 'bloc_lifecycle',
      'action': 'register',
      'bloc': T.toString(),
      'lifecycle': lifecycle.toString(),
      'scope': scope?.toString() ?? 'global',
    });
  }

  /// Check if a bloc type is registered.
  static bool isRegistered<T extends JuiceBloc<BlocState>>({Object? scope}) {
    final id = BlocId(T, scope ?? BlocId.globalScope);
    return _entries.containsKey(id);
  }

  /// Validate that a registration matches expected lifecycle.
  ///
  /// Throws [StateError] if the lifecycle doesn't match.
  /// Used by widgets to catch misconfiguration early.
  static void validateRegistration<T extends JuiceBloc<BlocState>>({
    Object? scope,
    required BlocLifecycle expectedLifecycle,
  }) {
    final id = BlocId(T, scope ?? BlocId.globalScope);
    final entry = _entries[id];

    if (entry == null) {
      throw StateError('Bloc $T (scope: $scope) not registered');
    }

    if (entry.lifecycle != expectedLifecycle) {
      // Log warning but don't throw - allows flexibility
      assert(() {
        debugPrint(
          'BlocScope: Widget expects $T with $expectedLifecycle, '
          'but registered with ${entry.lifecycle}',
        );
        return true;
      }());
    }
  }

  // ============================================================
  // Resolution
  // ============================================================

  /// Get a bloc instance (creates lazily if needed).
  ///
  /// For [BlocLifecycle.permanent] and [BlocLifecycle.feature] blocs,
  /// this is the standard way to access blocs.
  ///
  /// For [BlocLifecycle.leased] blocs, use [lease] instead.
  /// In debug mode, calling get() on a leased bloc throws an error.
  static T get<T extends JuiceBloc<BlocState>>({Object? scope}) {
    final id = BlocId(T, scope ?? BlocId.globalScope);
    final entry = _entries[id];

    if (entry == null) {
      throw StateError('Bloc $T (scope: $scope) not registered');
    }

    // Warn/throw for leased blocs
    if (entry.lifecycle == BlocLifecycle.leased) {
      assert(() {
        throw StateError(
          'Bloc $T is leased - use BlocScope.lease<$T>() instead of get()',
        );
      }());
      // In release mode, log warning and continue
      JuiceLoggerConfig.logger.log(
        'WARNING: get() called on leased bloc, use lease() instead',
        context: {'bloc': T.toString()},
      );
    }

    return _getOrCreate<T>(id, entry as BlocEntry<T>);
  }

  /// Acquire a lease on a bloc.
  ///
  /// Returns a [BlocLease] that provides access to the bloc.
  /// The bloc will not be auto-disposed while any lease is held.
  ///
  /// MUST be called in initState(), released in dispose().
  /// NEVER call in build().
  static BlocLease<T> lease<T extends JuiceBloc<BlocState>>({Object? scope}) {
    final id = BlocId(T, scope ?? BlocId.globalScope);
    final entry = _entries[id];

    if (entry == null) {
      throw StateError('Bloc $T (scope: $scope) not registered');
    }

    final typedEntry = entry as BlocEntry<T>;
    final bloc = _getOrCreate<T>(id, typedEntry);

    typedEntry.leaseCount++;

    // Track lease for leak detection
    LeakDetector.trackLeaseAcquire(id);

    JuiceLoggerConfig.logger.log('Lease acquired', context: {
      'type': 'bloc_lifecycle',
      'action': 'lease_acquire',
      'bloc': T.toString(),
      'leaseCount': typedEntry.leaseCount,
    });

    return BlocLease<T>(
      bloc,
      () => _releaseLease<T>(id),
    );
  }

  /// Acquire a lease asynchronously, waiting if bloc is closing.
  ///
  /// Use this when you need to acquire a lease and the bloc might
  /// be in the process of closing.
  static Future<BlocLease<T>> leaseAsync<T extends JuiceBloc<BlocState>>({
    Object? scope,
  }) async {
    final id = BlocId(T, scope ?? BlocId.globalScope);
    final entry = _entries[id];

    if (entry == null) {
      throw StateError('Bloc $T (scope: $scope) not registered');
    }

    // Wait for any in-progress close to complete
    if (entry.closingFuture != null) {
      await entry.closingFuture;
    }

    return lease<T>(scope: scope);
  }

  static T _getOrCreate<T extends JuiceBloc<BlocState>>(
    BlocId id,
    BlocEntry<T> entry,
  ) {
    // If closing, we have a problem - sync get can't wait
    if (entry.isClosing) {
      throw StateError(
        'Bloc ${id.type} is closing. Use leaseAsync() to wait for close.',
      );
    }

    // Create instance if needed
    if (entry.instance == null) {
      entry.instance = entry.factory();
      entry.createdAt = DateTime.now();

      // Track bloc creation for leak detection
      LeakDetector.trackBlocCreation(id);

      JuiceLoggerConfig.logger.log('Bloc instance created', context: {
        'type': 'bloc_lifecycle',
        'action': 'create',
        'bloc': id.type.toString(),
        'lifecycle': entry.lifecycle.toString(),
      });
    }

    return entry.instance!;
  }

  static void _releaseLease<T extends JuiceBloc<BlocState>>(BlocId id) {
    final entry = _entries[id];
    if (entry == null) return;

    // Don't decrement if already closing
    if (entry.isClosing) return;

    entry.leaseCount--;

    // Track lease release for leak detection
    LeakDetector.trackLeaseRelease(id);

    JuiceLoggerConfig.logger.log('Lease released', context: {
      'type': 'bloc_lifecycle',
      'action': 'lease_release',
      'bloc': id.type.toString(),
      'leaseCount': entry.leaseCount,
    });

    // Auto-dispose leased blocs when last lease releases
    if (entry.lifecycle == BlocLifecycle.leased && entry.leaseCount <= 0) {
      _closeEntry(id);
    }
  }

  // ============================================================
  // Disposal
  // ============================================================

  /// End a specific bloc instance.
  ///
  /// For [BlocLifecycle.feature] blocs, prefer using [FeatureScope.end].
  static Future<void> end<T extends JuiceBloc<BlocState>>({
    Object? scope,
  }) async {
    final id = BlocId(T, scope ?? BlocId.globalScope);
    await _closeEntry(id);
  }

  /// End all blocs associated with a FeatureScope.
  static Future<void> endFeature(FeatureScope scope) async {
    final futures = <Future<void>>[];

    for (final id in scope.managedBlocs) {
      futures.add(_closeEntry(id));
    }

    await Future.wait(futures);

    JuiceLoggerConfig.logger.log('Feature scope ended', context: {
      'type': 'bloc_lifecycle',
      'action': 'end_feature',
      'scope': scope.name,
      'blocsEnded': scope.managedBlocs.length,
    });
  }

  /// Dispose all blocs (app shutdown).
  ///
  /// In debug mode, checks for leaked leases and un-ended feature scopes.
  static Future<void> endAll() async {
    // Check for leaks before closing
    FeatureScope.debugCheckLeaks();

    // Close all blocs
    final futures = <Future<void>>[];
    for (final entry in _entries.entries) {
      if (entry.value.instance != null) {
        futures.add(_closeEntry(entry.key));
      }
    }
    await Future.wait(futures);

    // Leak detection in debug mode
    assert(() {
      final leaks = <String>[];

      for (final entry in _entries.entries) {
        final data = entry.value;

        if (data.lifecycle == BlocLifecycle.leased && data.leaseCount > 0) {
          leaks.add(
            'LEAK: ${entry.key.type} has ${data.leaseCount} unreleased leases',
          );
        }

        if (data.lifecycle == BlocLifecycle.feature && data.instance != null) {
          leaks.add(
            'LEAK: Feature bloc ${entry.key.type} was not ended before shutdown',
          );
        }
      }

      if (leaks.isNotEmpty) {
        debugPrint('=== BlocScope Leak Detection ===');
        for (final leak in leaks) {
          debugPrint(leak);
        }
        debugPrint('================================');
      }

      return true;
    }());

    _entries.clear();

    JuiceLoggerConfig.logger.log('All blocs ended', context: {
      'type': 'bloc_lifecycle',
      'action': 'end_all',
    });
  }

  static Future<void> _closeEntry(BlocId id) async {
    final entry = _entries[id];
    if (entry == null || entry.instance == null) return;

    // Already closing? Wait for it.
    if (entry.closingFuture != null) {
      await entry.closingFuture;
      return;
    }

    // Start close
    final bloc = entry.instance!;
    entry.closingFuture = bloc.close();

    JuiceLoggerConfig.logger.log('Bloc closing', context: {
      'type': 'bloc_lifecycle',
      'action': 'close',
      'bloc': id.type.toString(),
    });

    await entry.closingFuture;

    // Track bloc close for leak detection
    LeakDetector.trackBlocClose(id);

    // Only clear after close completes
    entry.instance = null;
    entry.closingFuture = null;
    entry.leaseCount = 0;
    entry.createdAt = null;
  }

  // ============================================================
  // Diagnostics
  // ============================================================

  /// Dump all registered blocs and their state (debug only).
  static void debugDump() {
    assert(() {
      debugPrint('=== BlocScope Debug Dump ===');
      for (final entry in _entries.entries) {
        final id = entry.key;
        final data = entry.value;
        debugPrint('''
  ${id.type} (scope: ${id.scopeKey})
    lifecycle: ${data.lifecycle}
    instance: ${data.instance != null ? 'active' : 'null'}
    leaseCount: ${data.leaseCount}
    isClosing: ${data.isClosing}
    createdAt: ${data.createdAt}
''');
      }
      debugPrint('=== End Dump ===');
      return true;
    }());
  }

  /// Get diagnostic info for a specific bloc.
  static BlocDiagnostics? diagnostics<T extends JuiceBloc<BlocState>>({
    Object? scope,
  }) {
    final id = BlocId(T, scope ?? BlocId.globalScope);
    final entry = _entries[id];
    if (entry == null) return null;

    return BlocDiagnostics(
      type: T,
      scope: scope,
      lifecycle: entry.lifecycle,
      isActive: entry.instance != null,
      leaseCount: entry.leaseCount,
      isClosing: entry.isClosing,
      createdAt: entry.createdAt,
    );
  }

  /// Clear all registrations (for testing).
  @visibleForTesting
  static Future<void> reset() async {
    await endAll();
    _entries.clear();
    FeatureScope.resetTracking();
    LeakDetector.reset();
  }
}
