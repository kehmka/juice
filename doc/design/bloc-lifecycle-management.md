# Bloc Lifecycle Management - Design Document

This document outlines the replacement of the current `BlocScope` LRU-based caching with a lifecycle-aware resolution system.

## Problem Statement

The current `BlocScope` uses LRU caching which is the wrong abstraction for bloc management:

- **LRU is memory-pressure heuristics** - it evicts based on access patterns
- **Lifecycle is semantic correctness** - blocs should live/die based on their purpose

Juice blocs are "building blocks" that hold streams, in-flight use cases, websockets, caches, etc. They need explicit lifecycle management, not cache eviction.

---

## Normative Rules (MUST/SHOULD)

These are the core invariants that prevent misuse:

### Resolution Rules

| Lifecycle | `get()` | `lease()` |
|-----------|---------|-----------|
| `permanent` | ALLOWED | ALLOWED (but unnecessary) |
| `feature` | ALLOWED | ALLOWED |
| `leased` | MUST throw in debug, warn in release | REQUIRED |

**Rule:** Any code that holds a bloc reference beyond the current synchronous call stack MUST hold a lease.

### Registration Rules

1. **Re-registration MUST match** - Registering the same `BlocId` with different factory or lifecycle MUST throw.
2. **Implicit registration** - When a widget registers a bloc on-demand, it SHOULD log in debug mode.

### Closing Rules

1. **No instance while closing** - If `closingFuture != null`, `get()` and `lease()` MUST await completion before creating new instance.
2. **close() is idempotent** - Multiple calls to `close()` MUST be safe and return the same Future.
3. **Lease release during close** - Releasing a lease while bloc is closing MUST be a no-op (already closing).

### Lease Rules

1. **Increment on mount** - Lease count increases in `initState()` or equivalent.
2. **Decrement on dispose** - Lease count decreases in `dispose()` or equivalent.
3. **Never in build()** - Lease operations MUST NOT occur in `build()` methods.
4. **Cross-bloc leases** - EventSubscription, RelayUseCaseBuilder, and any cross-bloc dependency MUST hold leases.

---

## Core Concepts

### 1. Lifecycle Enum

```dart
enum BlocLifecycle {
  /// Lives for entire app lifetime. Never auto-disposed.
  /// Use for: AuthBloc, SettingsBloc, AppBloc, ThemeBloc
  permanent,

  /// Lives for a feature/flow. Disposed when FeatureScope ends.
  /// Use for: CheckoutBloc, OnboardingBloc, WizardBloc
  feature,

  /// Lives while leases exist. Auto-disposed when last lease releases.
  /// Use for: FormBloc, SearchBloc, ItemDetailBloc
  leased,
}
```

### 2. Scope Keys

Multiple instances of the same bloc type must coexist safely:

- Two chat threads open → two `ChatBloc` instances
- Nested forms → two `FormBloc` instances
- List items with blocs → N `ItemBloc` instances

**Solution:** Key blocs by `(Type, scopeKey)` tuple.

```dart
// Same type, different instances
final chat1 = BlocScope.get<ChatBloc>(scope: 'thread-123');
final chat2 = BlocScope.get<ChatBloc>(scope: 'thread-456');
```

#### Scope Key Identity vs Equality

Scope keys use Dart's standard `==` operator for comparison. This means:

- **Strings/ints**: Equal by value (`'thread-123' == 'thread-123'`)
- **FeatureScope objects**: Equal by identity (two `FeatureScope('checkout')` are different)

**Guidelines:**

| Use Case | Recommended Key Type |
|----------|---------------------|
| Feature flows | `FeatureScope` object (identity) |
| Item-scoped (list items) | String/int ID |
| Route-scoped | Route name or path string |

**Warning:** Custom objects with overridden `==` may cause unexpected aliasing. Prefer primitives or `FeatureScope` for clarity.

### 3. Leases (Reference Counting)

A **lease** represents active usage of a bloc. Anything that depends on a bloc instance must:

1. Acquire a lease on mount/init
2. Release the lease on dispose/cleanup

This includes:
- UI widgets
- Cross-bloc subscriptions (EventSubscription, RelayUseCaseBuilder)
- Any other dependent code

**Critical rule:** Increment on mount, decrement on dispose — never in `build()`.

## Data Model

### BlocId

```dart
class BlocId {
  final Type type;
  final Object scopeKey;

  const BlocId(this.type, [this.scopeKey = const _GlobalScope()]);

  @override
  bool operator ==(Object other) =>
      other is BlocId && other.type == type && other.scopeKey == scopeKey;

  @override
  int get hashCode => Object.hash(type, scopeKey);
}

class _GlobalScope {
  const _GlobalScope();
}
```

### BlocEntry

```dart
class _BlocEntry<T extends JuiceBloc> {
  final T Function() factory;
  final BlocLifecycle lifecycle;

  T? instance;
  int leaseCount = 0;
  Future<void>? closingFuture;  // Prevents double-close race
  DateTime? createdAt;

  bool get isActive => instance != null && closingFuture == null;
  bool get isClosing => closingFuture != null;
}
```

## API Design

### BlocScope (Revised)

```dart
class BlocScope {
  static final Map<BlocId, _BlocEntry> _entries = {};

  /// Register a bloc factory with lifecycle behavior.
  static void register<T extends JuiceBloc>(
    T Function() factory, {
    BlocLifecycle lifecycle = BlocLifecycle.permanent,
    Object? scope,
  });

  /// Check if a bloc type is registered.
  static bool isRegistered<T extends JuiceBloc>({Object? scope});

  /// Get a bloc instance (creates lazily if needed).
  /// For leased blocs, prefer using lease() instead.
  static T get<T extends JuiceBloc>({Object? scope});

  /// Acquire a lease on a bloc. Returns bloc and release function.
  /// The bloc will not be disposed while any lease is held.
  static BlocLease<T> lease<T extends JuiceBloc>({Object? scope});

  /// End a feature-scoped bloc explicitly.
  /// Only valid for BlocLifecycle.feature blocs.
  static Future<void> end<T extends JuiceBloc>({Object? scope});

  /// End all blocs associated with a FeatureScope.
  static Future<void> endFeature(FeatureScope scope);

  /// Dispose all blocs (app shutdown).
  static Future<void> endAll();
}
```

### BlocLease

```dart
class BlocLease<T extends JuiceBloc> {
  final T bloc;
  final void Function() release;
  bool _released = false;

  BlocLease._(this.bloc, this.release);

  /// Release the lease. Safe to call multiple times.
  void dispose() {
    if (!_released) {
      _released = true;
      release();
    }
  }
}
```

### FeatureScope

For features with multiple blocs, use `FeatureScope` to manage them together:

```dart
class FeatureScope {
  final String name;
  final String _id = _generateId();  // Unique ID for identity
  final Set<BlocId> _managedBlocs = {};
  bool _ended = false;

  FeatureScope([this.name = 'unnamed']);

  static String _generateId() => DateTime.now().microsecondsSinceEpoch.toString();

  /// Track a bloc type as managed by this scope.
  /// Called automatically when registering with this scope.
  void _track(Type type) {
    if (_ended) throw StateError('FeatureScope "$name" already ended');
    _managedBlocs.add(BlocId(type, this));
  }

  /// End all blocs managed by this scope.
  Future<void> end() async {
    if (_ended) return;
    _ended = true;
    await BlocScope.endFeature(this);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is FeatureScope && other._id == _id);

  @override
  int get hashCode => _id.hashCode;

  @override
  String toString() => 'FeatureScope($name, $_id)';
}
```

**Usage:**

```dart
class CheckoutFlow {
  final scope = FeatureScope('checkout');

  void start() {
    // All these blocs share this scope's lifecycle
    BlocScope.register<CartBloc>(() => CartBloc(),
        lifecycle: BlocLifecycle.feature, scope: scope);
    BlocScope.register<PaymentBloc>(() => PaymentBloc(),
        lifecycle: BlocLifecycle.feature, scope: scope);
    BlocScope.register<ShippingBloc>(() => ShippingBloc(),
        lifecycle: BlocLifecycle.feature, scope: scope);
  }

  Future<void> complete() async {
    // Disposes CartBloc, PaymentBloc, ShippingBloc
    await scope.end();
  }
}
```

## Widget Integration

### StatelessJuiceWidget Changes

Widgets acquire leases internally using a stateful wrapper:

```dart
abstract class StatelessJuiceWidget<TBloc extends JuiceBloc>
    extends StatelessWidget {

  StatelessJuiceWidget({
    super.key,            // Let Flutter handle keys normally
    this.groups = const {"*"},
    this.scope,           // Optional scope key
    this.create,          // Optional factory for unregistered blocs
    this.lifecycle,       // Lifecycle if creating
  });

  final Set<String> groups;
  final Object? scope;
  final TBloc Function()? create;
  final BlocLifecycle? lifecycle;

  @override
  Widget build(BuildContext context) {
    return _BlocLeaseHolder<TBloc>(
      scope: scope,
      create: create,
      lifecycle: lifecycle ?? BlocLifecycle.leased,
      builder: (bloc) => _buildWithBloc(context, bloc),
    );
  }

  Widget _buildWithBloc(BuildContext context, TBloc bloc) {
    return JuiceAsyncBuilder<StreamStatus>(
      stream: bloc.stream.where((status) => _shouldRebuild(status)),
      initial: bloc.currentStatus,
      builder: (context, status) => onBuild(context, status),
      // ...
    );
  }
}
```

### _BlocLeaseHolder (Internal StatefulWidget)

```dart
class _BlocLeaseHolder<TBloc extends JuiceBloc> extends StatefulWidget {
  final Object? scope;
  final TBloc Function()? create;
  final BlocLifecycle lifecycle;
  final Widget Function(TBloc bloc) builder;

  const _BlocLeaseHolder({
    required this.builder,
    required this.lifecycle,
    this.scope,
    this.create,
    super.key,
  });

  @override
  State<_BlocLeaseHolder<TBloc>> createState() => _BlocLeaseHolderState<TBloc>();
}

class _BlocLeaseHolderState<TBloc extends JuiceBloc>
    extends State<_BlocLeaseHolder<TBloc>> {
  BlocLease<TBloc>? _lease;

  @override
  void initState() {
    super.initState();
    _acquireLease();
  }

  void _acquireLease() {
    final scope = widget.scope;

    // Register if needed (for widget-declared blocs)
    if (!BlocScope.isRegistered<TBloc>(scope: scope)) {
      if (widget.create != null) {
        // Log implicit registration in debug mode
        assert(() {
          debugPrint(
            'BlocScope: Widget implicitly registering $TBloc '
            '(scope: $scope, lifecycle: ${widget.lifecycle})'
          );
          return true;
        }());

        BlocScope.register<TBloc>(
          widget.create!,
          lifecycle: widget.lifecycle,
          scope: scope,
        );
      } else {
        throw StateError(
          'Bloc $TBloc not registered (scope: $scope) '
          'and no create factory provided'
        );
      }
    } else {
      // Validate that existing registration matches expected lifecycle
      // This prevents subtle bugs where different widgets expect different lifecycles
      BlocScope.validateRegistration<TBloc>(
        scope: scope,
        expectedLifecycle: widget.lifecycle,
      );
    }

    _lease = BlocScope.lease<TBloc>(scope: scope);
  }

  @override
  void dispose() {
    _lease?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return widget.builder(_lease!.bloc);
  }
}
```

## Cross-Bloc Dependencies

EventSubscription and RelayUseCaseBuilder must also hold leases:

```dart
class EventSubscription<TSourceBloc, TSourceEvent, TLocalEvent>
    implements UseCaseBuilderBase {

  BlocLease<TSourceBloc>? _sourceLease;

  void _initialize() {
    // Acquire lease instead of just resolving
    _sourceLease = BlocScope.lease<TSourceBloc>();
    _sourceBloc = _sourceLease!.bloc;

    _setupSubscription();
  }

  @override
  Future<void> close() async {
    await _subscription?.cancel();
    _sourceLease?.dispose();  // Release the lease
    // ...
  }
}
```

## Invariants

These must always hold:

1. **permanent** blocs ignore lease counts and never auto-dispose
2. **leased** blocs dispose only when `leaseCount` reaches 0
3. **feature** blocs require explicit `end()` or `FeatureScope.end()`
4. **close()** is idempotent and awaitable
5. No new instance created while previous is closing (`closingFuture` guard)
6. Lease increment on mount, decrement on dispose — **never in build()**

## Async Close Race Prevention

### Closing Logic

```dart
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

  await entry.closingFuture;

  // Only clear after close completes
  entry.instance = null;
  entry.closingFuture = null;
  entry.leaseCount = 0;
}
```

### Lease During Close

When `lease()` is called while a bloc is closing:

```dart
static Future<BlocLease<T>> lease<T extends JuiceBloc>({Object? scope}) async {
  final id = BlocId(T, scope ?? const _GlobalScope());
  final entry = _entries[id];

  if (entry == null) {
    throw StateError('Bloc $T not registered');
  }

  // If closing, wait for close to complete
  if (entry.closingFuture != null) {
    await entry.closingFuture;
    // After close, instance is null - create fresh
  }

  // Create instance if needed
  if (entry.instance == null) {
    entry.instance = entry.factory() as T;
    entry.createdAt = DateTime.now();
  }

  entry.leaseCount++;

  return BlocLease._(
    entry.instance as T,
    () => _releaseLease(id),
  );
}
```

### State Diagram

```
                  ┌─────────────────┐
                  │   NOT_CREATED   │
                  └────────┬────────┘
                           │ lease() or get()
                           ▼
                  ┌─────────────────┐
        ┌────────►│     ACTIVE      │◄────────┐
        │         └────────┬────────┘         │
        │                  │ last lease       │ lease()
        │                  │ released         │ (after close)
        │                  ▼                  │
        │         ┌─────────────────┐         │
        │         │    CLOSING      │─────────┘
        │         └────────┬────────┘
        │                  │ close() completes
        │                  ▼
        │         ┌─────────────────┐
        └─────────│   NOT_CREATED   │
                  └─────────────────┘
```

## Migration Path

### Phase 1: Add New API
- Add `BlocLifecycle` enum
- Add `BlocLease` class
- Add `FeatureScope` class
- Add `lease()` method to BlocScope
- Keep existing `get()` working

### Phase 2: Update Widgets
- Add `_BlocLeaseHolder` internal widget
- Update `StatelessJuiceWidget` to use leases
- Update `StatelessJuiceWidget2`, `StatelessJuiceWidget3`

### Phase 3: Update Cross-Bloc
- Update `EventSubscription` to use leases
- Update `RelayUseCaseBuilder` to use leases

### Phase 4: Remove Legacy
- Remove LRU cache code
- Remove `singleton` parameter from `get()`
- Update documentation

## Example Usage

### App-Level Blocs (permanent)

```dart
void main() {
  // Register permanent blocs at startup
  BlocScope.register<AuthBloc>(() => AuthBloc(),
      lifecycle: BlocLifecycle.permanent);
  BlocScope.register<SettingsBloc>(() => SettingsBloc(),
      lifecycle: BlocLifecycle.permanent);

  runApp(MyApp());
}

// Widget just declares dependency - no create needed
class ProfilePage extends StatelessJuiceWidget<AuthBloc> {
  ProfilePage() : super(groups: {'profile'});

  @override
  Widget onBuild(BuildContext context, StreamStatus status) {
    return Text('Welcome ${bloc.state.userName}');
  }
}
```

### Feature-Level Blocs (feature)

```dart
class CheckoutFeature {
  final scope = FeatureScope('checkout');

  void enter() {
    BlocScope.register<CartBloc>(() => CartBloc(),
        lifecycle: BlocLifecycle.feature, scope: scope);
  }

  Future<void> exit() => scope.end();
}

// In navigation
void onCheckoutPressed() {
  checkoutFeature.enter();
  navigator.push(CheckoutPage());
}

void onCheckoutComplete() {
  checkoutFeature.exit();
  navigator.pop();
}
```

### Widget-Level Blocs (leased)

```dart
// Widget declares bloc with factory - created on demand,
// disposed when last widget using it unmounts
class SearchPage extends StatelessJuiceWidget<SearchBloc> {
  SearchPage() : super(
    groups: {'results'},
    create: () => SearchBloc(),
    lifecycle: BlocLifecycle.leased,
  );

  @override
  Widget onBuild(BuildContext context, StreamStatus status) {
    return SearchResults(results: bloc.state.results);
  }
}
```

### Scoped Instances (same type, different instances)

```dart
// Chat list - each item has its own ChatBloc instance
class ChatListItem extends StatelessJuiceWidget<ChatBloc> {
  ChatListItem({required this.threadId}) : super(
    scope: threadId,  // Scope key
    create: () => ChatBloc(),
    lifecycle: BlocLifecycle.leased,
  );

  final String threadId;

  @override
  Widget onBuild(BuildContext context, StreamStatus status) {
    return ListTile(
      title: Text(bloc.state.lastMessage),
    );
  }
}
```

## Diagnostics API

For debugging and monitoring bloc lifecycle in development:

```dart
class BlocScope {
  /// Dump all registered blocs and their state (debug only)
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
    isClosing: ${data.closingFuture != null}
    createdAt: ${data.createdAt}
''');
      }
      debugPrint('=== End Dump ===');
      return true;
    }());
  }

  /// Get diagnostic info for a specific bloc
  static BlocDiagnostics? diagnostics<T extends JuiceBloc>({Object? scope}) {
    final id = BlocId(T, scope ?? const _GlobalScope());
    final entry = _entries[id];
    if (entry == null) return null;

    return BlocDiagnostics(
      type: T,
      scope: scope,
      lifecycle: entry.lifecycle,
      isActive: entry.instance != null,
      leaseCount: entry.leaseCount,
      isClosing: entry.closingFuture != null,
      createdAt: entry.createdAt,
    );
  }
}

class BlocDiagnostics {
  final Type type;
  final Object? scope;
  final BlocLifecycle lifecycle;
  final bool isActive;
  final int leaseCount;
  final bool isClosing;
  final DateTime? createdAt;

  const BlocDiagnostics({
    required this.type,
    required this.scope,
    required this.lifecycle,
    required this.isActive,
    required this.leaseCount,
    required this.isClosing,
    required this.createdAt,
  });
}
```

## Leak Detection (Debug Mode)

On app shutdown, assert that no blocs are leaked:

```dart
class BlocScope {
  /// Dispose all blocs and check for leaks (app shutdown)
  static Future<void> endAll() async {
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

        // Leased blocs should have 0 leases at shutdown
        if (data.lifecycle == BlocLifecycle.leased && data.leaseCount > 0) {
          leaks.add(
            'LEAK: ${entry.key.type} has ${data.leaseCount} unreleased leases'
          );
        }

        // Feature blocs should be ended before shutdown
        if (data.lifecycle == BlocLifecycle.feature && data.instance != null) {
          leaks.add(
            'LEAK: Feature bloc ${entry.key.type} was not ended before shutdown'
          );
        }
      }

      if (leaks.isNotEmpty) {
        debugPrint('=== BlocScope Leak Detection ===');
        for (final leak in leaks) {
          debugPrint(leak);
        }
        debugPrint('================================');
        // Optionally throw in debug to catch leaks early
        // throw StateError('Bloc leaks detected');
      }

      return true;
    }());

    _entries.clear();
  }
}
```

### FeatureScope Leak Detection

```dart
class FeatureScope {
  // Track all active feature scopes for leak detection
  static final Set<FeatureScope> _activeScopes = {};

  FeatureScope([this.name = 'unnamed']) {
    assert(() {
      _activeScopes.add(this);
      return true;
    }());
  }

  Future<void> end() async {
    if (_ended) return;
    _ended = true;

    assert(() {
      _activeScopes.remove(this);
      return true;
    }());

    await BlocScope.endFeature(this);
  }

  /// Check for un-ended feature scopes (call before app shutdown)
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
}
```

## Summary

| Aspect | LRU (Old) | Lifecycle (New) |
|--------|-----------|-----------------|
| Eviction trigger | Access pattern | Semantic lifecycle |
| Multiple instances | Awkward key param | First-class scope keys |
| Widget integration | Implicit | Explicit leases |
| Cross-bloc deps | Not tracked | Lease-based |
| Feature flows | Manual | FeatureScope |
| Close races | Possible | Prevented |
| Leak detection | None | Built-in (debug) |
| Diagnostics | None | debugDump(), diagnostics() |
| Mental model | "Cache" | "Ownership" |
