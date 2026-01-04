# Dependency Resolution and Bloc Lifecycle in Juice

## BlocScope Overview

BlocScope is Juice's built-in dependency resolution system that manages bloc instances and their lifecycles. It provides semantic lifecycle control with three options:

- **Permanent** - App-level blocs that live for the entire application lifetime
- **Feature** - Blocs scoped to a feature, disposed together via `FeatureScope`
- **Leased** - Widget-level blocs with automatic reference-counted disposal

### Basic Setup

```dart
void main() {
  // Register app-level blocs (live forever)
  BlocScope.register<AuthBloc>(
    () => AuthBloc(),
    lifecycle: BlocLifecycle.permanent,
  );

  BlocScope.register<SettingsBloc>(
    () => SettingsBloc(),
    lifecycle: BlocLifecycle.permanent,
  );

  runApp(MyApp());
}
```

### Bloc Registration Patterns

1. **Permanent Blocs** - App-level, live forever
```dart
BlocScope.register<CounterBloc>(
  () => CounterBloc(),
  lifecycle: BlocLifecycle.permanent,
);
```

2. **Feature Blocs** - Scoped to a feature flow
```dart
final checkoutScope = FeatureScope('checkout');

BlocScope.register<CartBloc>(
  () => CartBloc(),
  lifecycle: BlocLifecycle.feature,
  scope: checkoutScope,
);

// Later, when feature completes:
await BlocScope.endFeature(checkoutScope);
```

3. **Leased Blocs** - Widget-level, reference counted
```dart
BlocScope.register<FormBloc>(
  () => FormBloc(),
  lifecycle: BlocLifecycle.leased,
);

// In widget initState:
final lease = BlocScope.lease<FormBloc>();

// In widget dispose:
lease.dispose(); // Bloc closes when last lease releases
```

### Bloc Resolution

```dart
// Get permanent or feature bloc
final authBloc = BlocScope.get<AuthBloc>();

// Get leased bloc (acquire lease)
final lease = BlocScope.lease<FormBloc>();
final bloc = lease.bloc;

// Check if registered
if (BlocScope.isRegistered<MyBloc>()) {
  // ...
}

// Get diagnostics
final info = BlocScope.diagnostics<MyBloc>();
print('Active: ${info?.isActive}, Leases: ${info?.leaseCount}');
```

## GlobalBlocResolver (Legacy)

> **Note:** `GlobalBlocResolver` is still available for backwards compatibility, but `BlocScope` is the recommended approach for new code.

The GlobalBlocResolver provides a central point for bloc resolution throughout your app.

### Configuration

```dart
void main() {
  // Legacy setup (still works)
  GlobalBlocResolver().resolver = BlocResolver();

  // With custom resolver
  GlobalBlocResolver().resolver = CustomResolver();

  runApp(MyApp());
}
```

### Usage in Widgets

```dart
class ProfileWidget extends StatelessJuiceWidget<ProfileBloc> {
  // Resolver is handled automatically
  ProfileWidget({super.key, super.groups = const {"profile"}});
  
  @override
  Widget onBuild(BuildContext context, StreamStatus status) {
    // bloc is automatically resolved
    return Text(bloc.state.userName);
  }
}
```

### Custom Resolver Implementation

```dart
class CustomBlocResolver implements BlocDependencyResolver {
  @override
  T resolve<T extends JuiceBloc<BlocState>>({
    Map<String, dynamic>? args
  }) {
    // Custom resolution logic
    return customResolutionLogic<T>(args);
  }
}
```

## Integration with Flutter Modular

### Complete Modular Setup

```dart
// Core module with services
class CoreModule extends Module {
  @override
  List<Bind> get binds => [
    // Core services
    Bind.singleton((i) => ApiService()),
    Bind.singleton((i) => AuthService(i())),
    Bind.singleton((i) => StorageService()),
  ];
}

// App module that defines root setup
class AppModule extends Module {
  @override
  List<Module> get imports => [
    CoreModule(),
  ];

  @override
  List<Bind> get binds => [
    // Global blocs
    Bind.singleton((i) => AppBloc(i(), i())),
    Bind.singleton((i) => AuthBloc(i())),
  ];

  @override
  List<ModularRoute> get routes => [
    ChildRoute('/', child: (_, __) => HomePage()),
    ModuleRoute('/profile', module: ProfileModule()),
    ModuleRoute('/settings', module: SettingsModule()),
  ];
}

// Feature module with scoped dependencies
class ProfileModule extends Module {
  @override
  List<Bind> get binds => [
    // Feature-specific services
    Bind.singleton((i) => ProfileService(i())),
    
    // Scoped blocs
    Bind.factory((i) => ProfileBloc(i(), i())),
    Bind.factory((i) => ProfileSettingsBloc(i())),
  ];
  
  @override
  List<ModularRoute> get routes => [
    ChildRoute(
      '/',
      child: (context, args) => ProfilePage(),
    ),
    ChildRoute(
      '/settings',
      child: (context, args) => ProfileSettingsPage(),
    ),
  ];
}

// Modular resolver that integrates with Juice
class ModularBlocResolver implements BlocDependencyResolver {
  const ModularBlocResolver();
  
  @override
  T resolve<T extends JuiceBloc<BlocState>>({
    Map<String, dynamic>? args
  }) {
    try {
      // Try to get instance from current Modular scope
      return Modular.get<T>();
    } catch (e) {
      // Handle cases where bloc isn't registered in current scope
      throw BlocResolutionError(
        'Failed to resolve ${T.toString()}. '
        'Ensure it is bound in the appropriate Modular module.'
      );
    }
  }
  
  // Helper for disposing blocs when module is disposed
  void disposeBlocs() {
    try {
      Modular.dispose<ProfileBloc>();
      Modular.dispose<ProfileSettingsBloc>();
    } catch (_) {
      // Ignore errors if blocs are already disposed
    }
  }
}

// Application setup
void main() {
  // Set up Modular as the resolver
  GlobalBlocResolver().resolver = const ModularBlocResolver();
  
  runApp(ModularApp(
    module: AppModule(),
    child: MyApp(),
  ));
}

// Root app widget with Modular navigation
class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'My App',
      routeInformationParser: Modular.routeInformationParser,
      routerDelegate: Modular.routerDelegate,
      builder: (context, child) {
        return PopScope(
          onPopInvoked: (bool didPop) {
            // Clean up blocs when navigating back
            if (didPop) {
              (GlobalBlocResolver().resolver as ModularBlocResolver)
                .disposeBlocs();
            }
            return didPop;
          },
          child: child ?? const SizedBox(),
        );
      },
    );
  }
}

// Usage in widgets remains clean
class ProfilePage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          // Widgets get blocs through Modular scope
          ProfileHeader(),
          ProfileContent(),
          ProfileActions(),
        ],
      ),
    );
  }
}

// Widgets use blocs normally
class ProfileHeader extends StatelessJuiceWidget<ProfileBloc> {
  ProfileHeader({super.key, super.groups = const {"profile_header"}});
  
  @override
  Widget onBuild(BuildContext context, StreamStatus status) {
    // bloc is resolved through Modular
    return Text(bloc.state.userName);
  }
}
```

This setup provides:
- Clean module organization
- Proper scope management
- Automatic bloc cleanup
- Type-safe dependency injection
- Integration between Modular and Juice lifecycle

### Key Benefits

1. **Scoped Dependencies**
   - Blocs are scoped to their modules
   - Clean separation of features
   - Automatic cleanup on navigation

2. **Type Safety**
   - Full type safety through Modular
   - Clear error messages for missing dependencies
   - Compile-time dependency checking

3. **Resource Management**
   - Automatic disposal of scoped blocs
   - Proper cleanup on navigation
   - Memory leak prevention

## Scoping Strategies

### Single User Scope

For managing user-specific data and operations:

```dart
class UserScopedModule extends Module {
  final String userId;
  
  UserScopedModule(this.userId);

  @override
  List<Bind> get binds => [
    // Singleton within user scope
    Bind.singleton((i) => UserDataService(userId)),
    
    // Factory for each screen within scope
    Bind.factory((i) => UserProfileBloc(i())),
    Bind.factory((i) => UserPreferencesBloc(i())),
    
    // Singleton for shared user data
    Bind.singleton((i) => UserSessionBloc(i())),
  ];
  
  @override
  List<ModularRoute> get routes => [
    ChildRoute('/profile', child: (_, __) => UserProfilePage()),
    ChildRoute('/preferences', child: (_, __) => UserPreferencesPage()),
  ];
}

// Usage in app module
class AppModule extends Module {
  @override
  List<ModularRoute> get routes => [
    ModuleRoute(
      '/user/:id',
      module: (_, args) => UserScopedModule(args.params['id']),
    ),
  ];
}
```

### Feature Scope

For isolating feature-specific dependencies:

```dart
class ChatFeatureModule extends Module {
  @override
  List<Bind> get binds => [
    // Feature-wide singleton services
    Bind.singleton((i) => ChatService()),
    Bind.singleton((i) => MessageRepository()),
    
    // Shared bloc for feature
    Bind.singleton((i) => ChatSessionBloc(i())),
    
    // Screen-specific blocs
    Bind.factory((i) => ConversationBloc(i(), i())),
    Bind.factory((i) => MessageComposerBloc(i())),
  ];

  @override
  void dispose() {
    // Clean up feature resources
    Modular.dispose<ChatSessionBloc>();
    super.dispose();
  }
}
```

### Hierarchical Scope

For managing complex nested dependencies:

```dart
class OrganizationModule extends Module {
  final String orgId;
  
  OrganizationModule(this.orgId);
  
  @override
  List<Bind> get binds => [
    // Org-level singletons
    Bind.singleton((i) => OrganizationService(orgId)),
    Bind.singleton((i) => OrgDataBloc(i())),
  ];
  
  @override
  List<ModularRoute> get routes => [
    ModuleRoute(
      '/team/:teamId',
      module: (_, args) => TeamModule(
        orgId: orgId,
        teamId: args.params['teamId'],
      ),
    ),
  ];
}

class TeamModule extends Module {
  final String orgId;
  final String teamId;
  
  TeamModule({required this.orgId, required this.teamId});
  
  @override
  List<Bind> get binds => [
    // Team-level singletons
    Bind.singleton((i) => TeamService(orgId, teamId)),
    Bind.singleton((i) => TeamDataBloc(i())),
    
    // Member-specific factories
    Bind.factory((i) => MemberProfileBloc(i(), i())),
  ];
}
```

### Session Scope

For managing authenticated session state:

```dart
class SessionModule extends Module {
  final AuthToken token;
  
  SessionModule(this.token);

  @override
  List<Bind> get binds => [
    // Session-wide services
    Bind.singleton((i) => AuthenticatedApiService(token)),
    Bind.singleton((i) => SessionManager(token)),
    
    // Session-scoped blocs
    Bind.singleton((i) => SessionBloc(i())),
    Bind.factory((i) => UserDataBloc(i())),
  ];
  
  @override
  void dispose() {
    // Clean up session resources
    Modular.dispose<SessionBloc>();
    super.dispose();
  }
}

// Root module handling auth state
class RootModule extends Module {
  @override
  List<ModularRoute> get routes => [
    ModuleRoute(
      '/auth',
      module: AuthModule(),
      guards: [NotAuthenticatedGuard()],
    ),
    ModuleRoute(
      '/app',
      module: (_, args) => SessionModule(args.data['token']),
      guards: [AuthenticatedGuard()],
    ),
  ];
}
```

### Temporary Scope

For managing short-lived features:

```dart
class WizardModule extends Module {
  final String wizardId;
  
  WizardModule(this.wizardId);

  @override
  List<Bind> get binds => [
    // Wizard state management
    Bind.singleton((i) => WizardStateService()),
    Bind.singleton((i) => WizardBloc(i())),
    
    // Step-specific blocs
    Bind.factory((i) => StepOneBloc(i())),
    Bind.factory((i) => StepTwoBloc(i())),
  ];
  
  @override 
  void dispose() {
    // Clean up all wizard resources
    Modular.dispose<WizardBloc>();
    super.dispose();
  }
}

// Usage with cleanup
class WizardPage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return PopScope(
      onPopInvoked: (bool didPop) {
        if (didPop) {
          // Clean up wizard resources on exit
          Modular.dispose<WizardBloc>();
        }
        return didPop;
      },
      child: WizardContent(),
    );
  }
}
```

Key Considerations for Scoping:

1. **Lifetime Management**
   - Consider how long dependencies should live
   - Plan cleanup strategies
   - Handle navigation state

2. **Resource Sharing**
   - Decide what should be shared across scopes
   - Balance memory usage with performance
   - Consider data synchronization needs

3. **Performance Impact**
   - Monitor memory usage
   - Profile scope creation/destruction
   - Optimize scope boundaries

4. **Testing Strategy**
   - Test scope isolation
   - Verify cleanup behavior
   - Mock scope dependencies

## Bloc Lifecycle Management

### Instance Management

```dart
class BlocScope {
  // Singleton instances
  static final Map<String, JuiceBloc> _instances = {};
  
  // LRU cache for non-singleton instances
  static final Map<String, LinkedHashMap<dynamic, JuiceBloc>> _lruCaches = {};
  
  // Get bloc instance
  static T get<T extends JuiceBloc>({
    dynamic key,
    int maxCacheSize = 100,
    bool singleton = true,
  }) {
    final typeStr = T.toString();
    
    // Handle singleton case
    if (singleton) {
      return _getSingleton<T>(typeStr);
    }
    
    // Handle scoped instance
    return _getScopedInstance<T>(
      typeStr,
      key,
      maxCacheSize,
    );
  }
  
  // Clear instances
  static void clear<T extends JuiceBloc>() {
    final typeStr = T.toString();
    
    // Clear singleton
    if (_instances.containsKey(typeStr)) {
      _instances[typeStr]?.dispose();
      _instances.remove(typeStr);
    }
    
    // Clear cached instances
    if (_lruCaches.containsKey(typeStr)) {
      final cache = _lruCaches[typeStr]!;
      for (final bloc in cache.values) {
        bloc.dispose();
      }
      cache.clear();
      _lruCaches.remove(typeStr);
    }
  }
}
```

### Automatic Cleanup

```dart
class MyHomePage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return PopScope(
      onPopInvoked: (bool didPop) {
        // Clean up blocs when page is popped
        BlocScope.clear<ProfileBloc>();
        BlocScope.clear<SettingsBloc>();
        return didPop;
      },
      child: Scaffold(
        body: Column(
          children: [
            ProfileWidget(),
            SettingsWidget(),
          ],
        ),
      ),
    );
  }
}
```

### Memory Management

```dart
class AppBloc extends JuiceBloc<AppState> {
  AppBloc() : super(
    AppState.initial(),
    [
      // Use cases
    ],
    [], // Aviators
  ) {
    // Setup any resources
    _initialize();
  }
  
  Future<void> _initialize() async {
    // Initialize resources
  }
  
  @override
  Future<void> close() async {
    // Clean up resources
    await _cleanupResources();
    
    // Close use cases and aviators
    await super.close();
  }
  
  Future<void> _cleanupResources() async {
    // Custom cleanup logic
  }
}
```

## Best Practices

### 1. Dependency Organization

```dart
// Group related dependencies
class AuthModule {
  static void register() {
    // Register services
    BlocScope.registerFactory<AuthService>(
      () => AuthService(),
    );
    
    // Register blocs with dependencies
    BlocScope.registerFactory<AuthBloc>(
      () => AuthBloc(
        BlocScope.get<AuthService>(),
      ),
    );
  }
}
```

### 2. Scoped Instances

```dart
// User-specific bloc
class UserProfileBloc extends JuiceBloc<UserProfileState> {
  final String userId;
  
  UserProfileBloc(this.userId) : super(/*...*/);
}

// Get user-specific instance
final userBloc = BlocScope.get<UserProfileBloc>(
  key: userId,
  singleton: false,
);
```

### 3. Testing Support

```dart
void main() {
  setUp(() {
    // Register test dependencies
    BlocScope.registerFactory<MockAuthService>(
      () => MockAuthService(),
    );
    
    BlocScope.registerFactory<AuthBloc>(
      () => AuthBloc(
        BlocScope.get<MockAuthService>(),
      ),
    );
  });
  
  tearDown(() {
    // Clean up after tests
    BlocScope.clearAll();
  });
  
  test('auth bloc test', () {
    final bloc = BlocScope.get<AuthBloc>();
    // Test logic
  });
}
```

### 4. Custom Resolution

```dart
// Multi-tenant resolver that manages blocs per tenant
class TenantBlocResolver implements BlocDependencyResolver {
  final String tenantId;
  final Map<String, Map<Type, JuiceBloc>> _tenantBlocs = {};
  
  TenantBlocResolver(this.tenantId);
  
  @override
  T resolve<T extends JuiceBloc<BlocState>>({
    Map<String, dynamic>? args
  }) {
    // Get or create tenant-specific bloc map
    var blocMap = _tenantBlocs[tenantId] ??= {};
    
    // Create new bloc if not exists for this tenant
    return blocMap.putIfAbsent(T, () {
      // Create tenant-specific services
      final services = _createTenantServices(tenantId);
      
      // Initialize bloc with tenant services
      if (T == OrderBloc) {
        return OrderBloc(services.orderService) as T;
      } else if (T == InventoryBloc) {
        return InventoryBloc(services.inventoryService) as T;
      }
      
      throw BlocResolutionError('Unsupported bloc type: $T');
    }) as T;
  }
  
  void disposeTenant(String tenantId) {
    final blocs = _tenantBlocs.remove(tenantId);
    if (blocs != null) {
      for (final bloc in blocs.values) {
        bloc.close();
      }
    }
  }
}

// Feature flag based resolver that provides different bloc implementations
class FeatureFlagBlocResolver implements BlocDependencyResolver {
  final FeatureFlags _flags;
  final Map<Type, JuiceBloc> _blocs = {};
  
  FeatureFlagBlocResolver(this._flags);
  
  @override
  T resolve<T extends JuiceBloc<BlocState>>({
    Map<String, dynamic>? args
  }) {
    return _blocs.putIfAbsent(T, () {
      // Provide different implementations based on feature flags
      if (T == PaymentBloc) {
        return _flags.newPaymentSystem
          ? NewPaymentBloc(paymentService)
          : LegacyPaymentBloc(paymentService) as T;
      }
      
      if (T == CheckoutBloc) {
        return _flags.experimentalCheckout
          ? ExperimentalCheckoutBloc(checkoutService)
          : StandardCheckoutBloc(checkoutService) as T;
      }
      
      throw BlocResolutionError('Unsupported bloc type: $T');
    }) as T;
  }
}

// Environment-aware resolver for different deployment contexts
class EnvironmentBlocResolver implements BlocDependencyResolver {
  final Environment _environment;
  final Map<Type, JuiceBloc> _blocs = {};
  
  EnvironmentBlocResolver(this._environment);
  
  @override
  T resolve<T extends JuiceBloc<BlocState>>({
    Map<String, dynamic>? args
  }) {
    return _blocs.putIfAbsent(T, () {
      if (T == ApiBloc) {
        switch (_environment) {
          case Environment.development:
            return DevApiBloc(mockApiService) as T;
          case Environment.staging:
            return StagingApiBloc(stagingApiService) as T;
          case Environment.production:
            return ProductionApiBloc(productionApiService) as T;
        }
      }
      
      throw BlocResolutionError('Unsupported bloc type: $T');
    }) as T;
  }
}

// Usage examples:

// Multi-tenant setup
void configureTenantApp() {
  final resolver = TenantBlocResolver(currentTenant);
  GlobalBlocResolver().resolver = resolver;
  
  // Later, when switching tenants:
  resolver.disposeTenant(oldTenant);
  // Create new resolver for new tenant
}

// Feature flag setup
void configureFeatureFlags() {
  final flags = FeatureFlags(
    newPaymentSystem: true,
    experimentalCheckout: false,
  );
  GlobalBlocResolver().resolver = FeatureFlagBlocResolver(flags);
}

// Environment setup
void configureEnvironment() {
  final env = Environment.development;
  GlobalBlocResolver().resolver = EnvironmentBlocResolver(env);
}

// Composite resolver that combines multiple strategies
class CompositeResolver implements BlocDependencyResolver {
  final Map<Type, BlocDependencyResolver> _resolvers;
  final BlocDependencyResolver _defaultResolver;
  
  CompositeResolver({
    required Map<Type, BlocDependencyResolver> resolvers,
    required BlocDependencyResolver defaultResolver,
  }) : _resolvers = resolvers,
       _defaultResolver = defaultResolver;
  
  @override
  T resolve<T extends JuiceBloc<BlocState>>({
    Map<String, dynamic>? args
  }) {
    // Use specific resolver if available, otherwise fallback to default
    final resolver = _resolvers[T] ?? _defaultResolver;
    return resolver.resolve<T>(args: args);
  }
}

// Setup with multiple resolution strategies
void configureApp() {
  final tenantResolver = TenantBlocResolver(currentTenant);
  final featureResolver = FeatureFlagBlocResolver(flags);
  
  GlobalBlocResolver().resolver = CompositeResolver(
    resolvers: {
      // Tenant-specific blocs
      OrderBloc: tenantResolver,
      InventoryBloc: tenantResolver,
      
      // Feature flag dependent blocs
      PaymentBloc: featureResolver,
      CheckoutBloc: featureResolver,
    },
    defaultResolver: BlocResolver(),
  );
}
```

These custom resolvers demonstrate more practical use cases:

1. **Multi-tenant Resolution**
   - Manages separate bloc instances per tenant
   - Proper cleanup when switching tenants
   - Tenant-specific service initialization

2. **Feature Flag Resolution**
   - Different implementations based on flags
   - Support for A/B testing
   - Gradual feature rollout

3. **Environment Resolution**
   - Environment-specific implementations
   - Development vs production behavior
   - Safe testing environments

4. **Composite Resolution**
   - Combines multiple resolution strategies
   - Flexible bloc resolution rules
   - Clean fallback behavior

Remember:
- Consider bloc lifecycle when designing your app
- Clean up resources properly
- Use scoped instances when appropriate
- Test dependency resolution thoroughly