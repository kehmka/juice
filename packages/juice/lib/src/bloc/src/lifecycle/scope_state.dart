import 'package:flutter/foundation.dart';
import '../bloc_state.dart';
import 'feature_scope.dart';

/// Phase of a scope's lifecycle.
enum ScopePhase {
  /// Scope is running normally
  active,

  /// Cleanup in progress, scope is ending
  ending,
}

/// Information about a tracked scope.
@immutable
class ScopeInfo {
  /// Unique identifier - primary key.
  /// Generated via monotonic counter on ScopeBloc (deterministic, collision-free).
  final String id;

  /// Human-readable name (can collide across instances).
  final String name;

  /// Current phase of the scope.
  final ScopePhase phase;

  /// When the scope started.
  final DateTime startedAt;

  /// Reference to the FeatureScope for disposal.
  final FeatureScope scope;

  const ScopeInfo({
    required this.id,
    required this.name,
    required this.phase,
    required this.startedAt,
    required this.scope,
  });

  /// Create a copy with updated phase.
  ScopeInfo copyWith({ScopePhase? phase}) {
    return ScopeInfo(
      id: id,
      name: name,
      phase: phase ?? this.phase,
      startedAt: startedAt,
      scope: scope,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ScopeInfo && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() =>
      'ScopeInfo(id: $id, name: $name, phase: $phase, startedAt: $startedAt)';
}

/// State for ScopeBloc tracking active scopes.
@immutable
class ScopeState extends BlocState {
  /// Active scopes keyed by unique ID.
  final Map<String, ScopeInfo> scopes;

  const ScopeState({
    this.scopes = const {},
  });

  /// Lookup scopes by name (may return multiple if names collide).
  List<ScopeInfo> byName(String name) =>
      scopes.values.where((s) => s.name == name).toList();

  /// Check if any scope with this name is active.
  bool isActive(String name) =>
      scopes.values.any((s) => s.name == name && s.phase == ScopePhase.active);

  /// Get all scopes in a specific phase.
  List<ScopeInfo> inPhase(ScopePhase phase) =>
      scopes.values.where((s) => s.phase == phase).toList();

  /// Create a copy with updated scopes.
  ScopeState copyWith({
    Map<String, ScopeInfo>? scopes,
  }) {
    return ScopeState(
      scopes: scopes ?? this.scopes,
    );
  }

  @override
  String toString() => 'ScopeState(scopes: ${scopes.length})';
}

/// Predefined rebuild groups for scope state.
abstract class ScopeGroups {
  /// Group for any active scope change.
  static const active = 'scope:active';

  /// Group for a specific scope name.
  static String byName(String name) => 'scope:name:$name';

  /// Group for a specific scope ID.
  static String byId(String id) => 'scope:id:$id';
}
