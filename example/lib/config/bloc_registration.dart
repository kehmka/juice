import 'package:juice/juice.dart';
import '../blocs/blocs.dart';
import '../services/services.dart';

class BlocRegistry {
  static void initialize(DeepLinkConfig deeplinkconfig) {
    BlocScope.registerFactory<AppBloc>(
        () => AppBloc(deeplinkconfig: deeplinkconfig));
    BlocScope.registerFactory<CounterBloc>(() => CounterBloc());
    BlocScope.registerFactory<TodoBloc>(() => TodoBloc());
    BlocScope.registerFactory<ChatBloc>(() => ChatBloc(WebSocketService()));
    BlocScope.registerFactory<FileUploadBloc>(() => FileUploadBloc());
    BlocScope.registerFactory<FormBloc>(() => FormBloc());
    BlocScope.registerFactory<OnboardingBloc>(() => OnboardingBloc());
    BlocScope.registerFactory<WeatherBloc>(() => WeatherBloc());
    BlocScope.registerFactory<SettingsBloc>(() => SettingsBloc());
  }
}
