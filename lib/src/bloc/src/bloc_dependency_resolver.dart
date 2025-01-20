import "package:juice/juice.dart";

/// Base interface for resolving bloc dependencies.
///
/// This abstract class defines how blocs are resolved/retrieved throughout the application.
/// Implementations can provide different strategies for bloc resolution like singleton,
/// scoped instances, or composite resolution.
abstract class BlocDependencyResolver {
  /// Resolves and returns an instance of the specified bloc type.
  ///
  /// [T] - The type of bloc to resolve, must extend JuiceBloc<BlocState>
  /// [args] - Optional arguments that can be passed to customize bloc creation
  ///
  /// Returns an instance of the requested bloc type.
  T resolve<T extends JuiceBloc<BlocState>>({Map<String, dynamic>? args});

  void disposeAll() {}
}

/// Default implementation that resolves blocs from a global BlocScope.
///
/// This resolver uses a simple singleton pattern where all blocs are retrieved
/// from a global scope. Suitable for simpler applications with straightforward
/// dependency needs.
class BlocResolver implements BlocDependencyResolver {
  @override
  T resolve<T extends JuiceBloc<BlocState>>({Map<String, dynamic>? args}) {
    return BlocScope.get<T>();
  }

  /// Disposes all blocs and clears the registry.
  ///
  /// Calls `BlocScope.clearAll()` to ensure all registered blocs
  /// are disposed and resources are cleaned up.

  @override
  void disposeAll() {
    JuiceLoggerConfig.logger.log('Disposing all blocs through BlocResolver');
    BlocScope.clearAll();
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
  void disposeAll() {
    for (var resolver in resolvers.values) {
      resolver.disposeAll();
    }
  }
}
