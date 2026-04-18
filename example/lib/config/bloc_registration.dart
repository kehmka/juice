import 'package:juice/juice.dart';
import '../blocs/blocs.dart';
import '../services/services.dart';

class BlocRegistry {
  static void initialize(DeepLinkConfig deeplinkconfig) {
    // ScopeLifecycleBloc powers feature-scope lifecycle demos and cleanup.
    BlocScope.register<ScopeLifecycleBloc>(
      () => ScopeLifecycleBloc(),
      lifecycle: BlocLifecycle.permanent,
    );

    // App-level blocs - global services for the showcase shell.
    BlocScope.register<AppBloc>(
      () => AppBloc(deeplinkconfig: deeplinkconfig),
      lifecycle: BlocLifecycle.permanent,
    );
    BlocScope.register<AuthBloc>(
      () => AuthBloc(),
      lifecycle: BlocLifecycle.permanent,
    );
    BlocScope.register<SettingsBloc>(
      () => SettingsBloc(),
      lifecycle: BlocLifecycle.permanent,
    );

    // Screen-owned examples use leased lifecycle so the showcase actually
    // demonstrates Juice ownership semantics instead of defaulting everything
    // to app-lifetime state.
    BlocScope.register<CounterBloc>(
      () => CounterBloc(),
      lifecycle: BlocLifecycle.leased,
    );
    BlocScope.register<TodoBloc>(
      () => TodoBloc(),
      lifecycle: BlocLifecycle.leased,
    );
    BlocScope.register<ChatBloc>(
      () => ChatBloc(WebSocketService()),
      lifecycle: BlocLifecycle.leased,
    );
    BlocScope.register<FileUploadBloc>(
      () => FileUploadBloc(),
      lifecycle: BlocLifecycle.leased,
    );
    BlocScope.register<FormBloc>(
      () => FormBloc(),
      lifecycle: BlocLifecycle.leased,
    );
    BlocScope.register<OnboardingBloc>(
      () => OnboardingBloc(),
      lifecycle: BlocLifecycle.leased,
    );
    BlocScope.register<UserProfileBloc>(
      () => UserProfileBloc(),
      lifecycle: BlocLifecycle.leased,
    );
    BlocScope.register<WeatherBloc>(
      () => WeatherBloc(),
      lifecycle: BlocLifecycle.leased,
    );

    // Relay demo blocs stay permanent because the page wires relays up once
    // and expects both sides to be available for the duration of the session.
    BlocScope.register<SourceBloc>(
      () => SourceBloc(),
      lifecycle: BlocLifecycle.permanent,
    );
    BlocScope.register<DestBloc>(
      () => DestBloc(),
      lifecycle: BlocLifecycle.permanent,
    );

    // Keep the advanced showcase permanent because the page mixes selectors,
    // direct callbacks, and sendAndWait demonstrations.
    BlocScope.register<FeaturesShowcaseBloc>(
      () => FeaturesShowcaseBloc(),
      lifecycle: BlocLifecycle.permanent,
    );

    // Lifecycle demo owns its own internal FeatureScope and notification wiring.
    BlocScope.register<LifecycleDemoBloc>(
      () => LifecycleDemoBloc(),
      lifecycle: BlocLifecycle.permanent,
    );

    // Enable leak detection so leased examples surface misuse during showcase work.
    BlocScope.enableLeakDetection();
  }
}
