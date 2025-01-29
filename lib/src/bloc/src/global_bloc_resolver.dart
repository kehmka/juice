import 'package:juice/juice.dart';

/// Global resolver for managing bloc dependencies throughout the application.
///
/// The GlobalBlocResolver provides a central point for resolving bloc instances.
/// It can work with different dependency injection systems by accepting any
/// implementation of [BlocDependencyResolver].
///
/// Example usage with default resolver:
/// ```dart
/// void main() {
///   GlobalBlocResolver().resolver = BlocResolver();
///   runApp(MyApp());
/// }
/// ```
///
/// Example with FlutterModular:
/// ```dart
/// void main() {
///   GlobalBlocResolver().resolver = ModularBlocResolver();
///   runApp(ModularApp(module: AppModule()));
/// }
/// ```
///
/// Example with composite resolvers:
/// ```dart
/// void main() {
///   GlobalBlocResolver().resolver = CompositeResolver({
///     AuthBloc: AuthBlocResolver(),
///     FeatureBloc: FeatureBlocResolver(),
///   });
///   runApp(MyApp());
/// }
/// ```
class GlobalBlocResolver {
  /// Singleton instance of the GlobalBlocResolver
  static final GlobalBlocResolver _instance = GlobalBlocResolver._internal();

  /// The active bloc dependency resolver
  ///
  /// Must be set during app initialization before any bloc resolution is attempted
  late BlocDependencyResolver resolver;

  /// Private constructor for singleton pattern
  GlobalBlocResolver._internal();

  /// Factory constructor that returns the singleton instance
  factory GlobalBlocResolver() => _instance;

  /// Resolves a bloc of the specified type using the configured resolver
  ///
  /// Type parameter `T` must extend `JuiceBloc` of `BlocState`
  ///
  /// Returns an instance of the requested bloc type
  ///
  /// Throws an exception if resolver is not configured or if bloc type cannot be resolved
  static T resolve<T extends JuiceBloc<BlocState>>() {
    return _instance.resolver.resolve<T>();
  }
}
