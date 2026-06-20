/// Per-entity async status — the item-grained companion to [StreamStatus].
///
/// `StreamStatus` models *one* transient transition for the whole bloc
/// ("the bloc is, right now, waiting/failing"). When a bloc owns a collection
/// whose items have **independent, possibly concurrent** async lifecycles
/// (re-read, upload, delete, retry…), "which items are in flight" is persistent,
/// queryable *state*, not a single pulse. Model it with an [EntityStatuses]
/// embedded in your [BlocState]; drive it from use cases (see
/// `BlocUseCase.guardEntity`) and read it in widgets via [EntityStatusX.when].
library;

/// The async lifecycle of a single entity. Mirrors the [StreamStatus]
/// vocabulary (idle / waiting / failure) at the entity grain.
sealed class EntityStatus {
  const EntityStatus();

  bool get isIdle => this is EntityIdle;
  bool get isWaiting => this is EntityWaiting;
  bool get isFailure => this is EntityFailure;
}

/// Nothing in flight for this entity (the default for any unknown key).
class EntityIdle extends EntityStatus {
  const EntityIdle();
  @override
  bool operator ==(Object other) => other is EntityIdle;
  @override
  int get hashCode => 0;
}

/// An operation is in progress for this entity.
class EntityWaiting extends EntityStatus {
  const EntityWaiting();
  @override
  bool operator ==(Object other) => other is EntityWaiting;
  @override
  int get hashCode => 1;
}

/// The entity's last operation failed — carries the [error] so the UI can show
/// it and offer a retry (the per-item failure surface a bloc-wide status can't
/// express).
class EntityFailure extends EntityStatus {
  final Object error;
  const EntityFailure(this.error);
  @override
  bool operator ==(Object other) =>
      other is EntityFailure && other.error == error;
  @override
  int get hashCode => Object.hash(2, error);
}

/// Pattern-match ergonomics, mirroring `StreamStatus.when`.
extension EntityStatusX on EntityStatus {
  /// Exhaustive match over the three states.
  T when<T>({
    required T Function() idle,
    required T Function() waiting,
    required T Function(Object error) failure,
  }) =>
      switch (this) {
        EntityWaiting() => waiting(),
        EntityFailure(:final error) => failure(error),
        _ => idle(),
      };

  /// Partial match with a required fallback.
  T maybeWhen<T>({
    T Function()? idle,
    T Function()? waiting,
    T Function(Object error)? failure,
    required T Function() orElse,
  }) =>
      switch (this) {
        EntityWaiting() => waiting?.call() ?? orElse(),
        EntityFailure(:final error) => failure?.call(error) ?? orElse(),
        _ => idle?.call() ?? orElse(),
      };
}

/// An immutable map of `entity key → `[EntityStatus]. Absent keys read as
/// [EntityIdle], so only in-flight / failed keys are ever stored (the map stays
/// small). All mutators return a new instance — safe to hold in [BlocState] and
/// diff for rebuilds.
class EntityStatuses<K> {
  final Map<K, EntityStatus> _statuses;

  const EntityStatuses([Map<K, EntityStatus> statuses = const {}])
      : _statuses = statuses;

  /// Status for [key]; [EntityIdle] when nothing is tracked for it.
  EntityStatus statusOf(K key) => _statuses[key] ?? const EntityIdle();

  /// Whether [key] is currently waiting.
  bool isWaiting(K key) => statusOf(key).isWaiting;

  /// Whether [key]'s last operation failed.
  bool isFailure(K key) => statusOf(key).isFailure;

  /// True if any tracked entity is waiting (e.g. to show a list-level spinner).
  bool get anyWaiting => _statuses.values.any((s) => s.isWaiting);

  /// The keys currently waiting.
  Iterable<K> get waitingKeys =>
      _statuses.entries.where((e) => e.value.isWaiting).map((e) => e.key);

  /// The keys currently in a failure state.
  Iterable<K> get failedKeys =>
      _statuses.entries.where((e) => e.value.isFailure).map((e) => e.key);

  /// True when nothing is tracked (every entity is idle).
  bool get isEmpty => _statuses.isEmpty;

  /// True when at least one entity is waiting or failed.
  bool get isNotEmpty => _statuses.isNotEmpty;

  /// Number of tracked (waiting or failed) entities — not the collection size.
  int get length => _statuses.length;

  /// Mark [key] as waiting.
  EntityStatuses<K> waiting(K key) => _set(key, const EntityWaiting());

  /// Mark [key] as failed with [error].
  EntityStatuses<K> failure(K key, Object error) =>
      _set(key, EntityFailure(error));

  /// Clear [key] back to idle (removes it — idle is the absence of an entry).
  EntityStatuses<K> idle(K key) {
    if (!_statuses.containsKey(key)) return this;
    return EntityStatuses<K>(
        Map<K, EntityStatus>.from(_statuses)..remove(key));
  }

  /// Clear every tracked entity.
  EntityStatuses<K> clear() =>
      _statuses.isEmpty ? this : EntityStatuses<K>(const {});

  EntityStatuses<K> _set(K key, EntityStatus status) =>
      EntityStatuses<K>(Map<K, EntityStatus>.from(_statuses)..[key] = status);

  @override
  bool operator ==(Object other) {
    if (other is! EntityStatuses<K>) return false;
    if (other._statuses.length != _statuses.length) return false;
    for (final entry in _statuses.entries) {
      if (other._statuses[entry.key] != entry.value) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hashAllUnordered(
      _statuses.entries.map((e) => Object.hash(e.key, e.value)));

  @override
  String toString() => 'EntityStatuses($_statuses)';
}
