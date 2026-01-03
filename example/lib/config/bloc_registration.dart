import 'package:juice/juice.dart';
import '../blocs/blocs.dart';
import '../services/services.dart';

class BlocRegistry {
  static void initialize(DeepLinkConfig deeplinkconfig) {
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
  }
}
