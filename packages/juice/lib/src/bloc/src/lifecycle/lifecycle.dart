/// Bloc lifecycle management system.
///
/// This module provides semantic lifecycle management for blocs,
/// replacing LRU-based caching with explicit lifecycle control.
library lifecycle;

export 'bloc_lifecycle.dart';
export 'bloc_id.dart';
export 'bloc_lease.dart';
export 'bloc_entry.dart';
export 'bloc_diagnostics.dart';
export 'feature_scope.dart';
export 'leak_detector.dart';

// ScopeLifecycleBloc - reactive lifecycle events for FeatureScope
export 'cleanup_barrier.dart';
export 'scope_lifecycle_bloc.dart';
export 'scope_state.dart';
export 'scope_events.dart';
export 'scope_use_cases.dart';
