import 'package:juice/juice.dart';
import '../blocs/blocs.dart';
import '../services/services.dart';

class BlocRegistry {
  static void initialize(DeepLinkConfig deeplinkconfig) {
    // ScopeLifecycleBloc - must be registered first for scope lifecycle management
    BlocScope.register<ScopeLifecycleBloc>(
      () => ScopeLifecycleBloc(),
      lifecycle: BlocLifecycle.permanent,
    );

    // App-level blocs - permanent lifecycle (live for entire app lifetime)
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

    // Feature blocs - permanent for now, could be feature-scoped later
    BlocScope.register<CounterBloc>(
      () => CounterBloc(),
      lifecycle: BlocLifecycle.permanent,
    );
    BlocScope.register<TodoBloc>(
      () => TodoBloc(),
      lifecycle: BlocLifecycle.permanent,
    );
    BlocScope.register<ChatBloc>(
      () => ChatBloc(WebSocketService()),
      lifecycle: BlocLifecycle.permanent,
    );
    BlocScope.register<FileUploadBloc>(
      () => FileUploadBloc(),
      lifecycle: BlocLifecycle.permanent,
    );
    BlocScope.register<FormBloc>(
      () => FormBloc(),
      lifecycle: BlocLifecycle.permanent,
    );
    BlocScope.register<OnboardingBloc>(
      () => OnboardingBloc(),
      lifecycle: BlocLifecycle.permanent,
    );
    BlocScope.register<UserProfileBloc>(
      () => UserProfileBloc(),
      lifecycle: BlocLifecycle.permanent,
    );
    BlocScope.register<WeatherBloc>(
      () => WeatherBloc(),
      lifecycle: BlocLifecycle.permanent,
    );

    // Relay demo blocs
    BlocScope.register<SourceBloc>(
      () => SourceBloc(),
      lifecycle: BlocLifecycle.permanent,
    );
    BlocScope.register<DestBloc>(
      () => DestBloc(),
      lifecycle: BlocLifecycle.permanent,
    );

    // Features showcase - demonstrates new Juice features
    BlocScope.register<FeaturesShowcaseBloc>(
      () => FeaturesShowcaseBloc(),
      lifecycle: BlocLifecycle.permanent,
    );

    // Lifecycle demo - demonstrates ScopeLifecycleBloc cleanup
    BlocScope.register<LifecycleDemoBloc>(
      () => LifecycleDemoBloc(),
      lifecycle: BlocLifecycle.permanent,
    );

    // Enable leak detection in debug mode (demonstrates LeakDetector feature)
    BlocScope.enableLeakDetection();
  }
}
