/// Uniquely identifies a bloc instance by type and scope.
///
/// Multiple instances of the same bloc type can coexist when they
/// have different scope keys. This enables patterns like:
/// - Multiple chat threads (different thread IDs)
/// - Nested forms (different form instances)
/// - List items with individual blocs
class BlocId {
  /// Creates a BlocId with a type and optional scope key.
  ///
  /// If no scope key is provided, uses [globalScope] which represents
  /// the default global/singleton scope.
  const BlocId(this.type, [this.scopeKey = globalScope]);

  /// The bloc type this ID represents.
  final Type type;

  /// The scope key for this bloc instance.
  ///
  /// Different scope keys allow multiple instances of the same type.
  final Object scopeKey;

  /// The default global scope for singleton-style blocs.
  static const Object globalScope = _GlobalScope();

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is BlocId && other.type == type && other.scopeKey == scopeKey);

  @override
  int get hashCode => Object.hash(type, scopeKey);

  @override
  String toString() => 'BlocId($type, $scopeKey)';
}

/// Sentinel object representing the global/default scope.
class _GlobalScope {
  const _GlobalScope();

  @override
  String toString() => 'GlobalScope';
}
