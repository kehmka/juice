import "package:juice/juice.dart";

/// Base interface for resolving bloc dependencies.
///
/// This abstract class defines how blocs are resolved/retrieved throughout the application.
/// Implementations can provide different strategies for bloc resolution like singleton,
/// scoped instances, or composite resolution.
abstract class BlocDependencyResolver {
  /// Resolves and returns an instance of the specified bloc type.
  ///
  /// Type parameter `T` must extend `JuiceBloc` of `BlocState`
  /// [args] - Optional arguments that can be passed to customize bloc creation
  ///
  /// Returns an instance of the requested bloc type.
  T resolve<T extends JuiceBloc<BlocState>>({Map<String, dynamic>? args});

  /// Acquires a lease on a bloc for reference-counted lifecycle management.
  ///
  /// For [BlocLifecycle.leased] blocs, this is the required way to access them.
  /// The lease must be released when the bloc is no longer needed.
  BlocLease<T> lease<T extends JuiceBloc<BlocState>>({Object? scope}) {
    return BlocScope.lease<T>(scope: scope);
  }

  Future<void> disposeAll() async {}
}

/// Default implementation that resolves blocs from a global BlocScope.
///
/// This resolver uses the lifecycle-aware BlocScope for bloc management.
/// Suitable for most applications with straightforward dependency needs.
class BlocResolver implements BlocDependencyResolver {
  @override
  T resolve<T extends JuiceBloc<BlocState>>({Map<String, dynamic>? args}) {
    return BlocScope.get<T>();
  }

  @override
  BlocLease<T> lease<T extends JuiceBloc<BlocState>>({Object? scope}) {
    return BlocScope.lease<T>(scope: scope);
  }

  /// Disposes all blocs and clears the registry.
  ///
  /// Calls `BlocScope.endAll()` to ensure all registered blocs
  /// are disposed and resources are cleaned up.
  @override
  Future<void> disposeAll() async {
    JuiceLoggerConfig.logger.log('Disposing all blocs through BlocResolver');
    await BlocScope.endAll();
  }
}

/// A resolver that delegates to different resolvers based on bloc type.
///
/// This implements the composite pattern, allowing different resolution strategies
/// for different bloc types. Useful for more complex applications where different
/// blocs need different resolution strategies.
class CompositeResolver implements BlocDependencyResolver {
  /// Maps bloc types to their specific resolvers
  final Map<Type, BlocDependencyResolver> resolvers;

  /// Creates a composite resolver with a map of type-specific resolvers
  ///
  /// [resolvers] - Map where keys are bloc types and values are their resolvers
  CompositeResolver(this.resolvers);

  @override
  T resolve<T extends JuiceBloc<BlocState>>({Map<String, dynamic>? args}) {
    // Find the resolver for the requested type or throw if none exists
    final resolver =
        resolvers[T] ?? (throw Exception('No resolver found for $T'));
    return resolver.resolve<T>();
  }

  @override
  BlocLease<T> lease<T extends JuiceBloc<BlocState>>({Object? scope}) {
    final resolver = resolvers[T];
    if (resolver != null) {
      return resolver.lease<T>(scope: scope);
    }
    return BlocScope.lease<T>(scope: scope);
  }

  @override
  Future<void> disposeAll() async {
    for (var resolver in resolvers.values) {
      await resolver.disposeAll();
    }
  }
}
