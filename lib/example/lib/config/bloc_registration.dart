import 'package:juice/example/lib/blocs/form/form_bloc.dart';
import 'package:juice/juice.dart';
import 'package:juice/example/lib/blocs/blocs.dart';

import 'package:juice/example/lib/services/services.dart';

class BlocRegistry {
  static void initialize(DeepLinkConfig deeplinkconfig) {
    BlocScope.registerFactory<AppBloc>(
        () => AppBloc(deeplinkconfig: deeplinkconfig));
    BlocScope.registerFactory<CounterBloc>(() => CounterBloc());
    BlocScope.registerFactory<TodoBloc>(() => TodoBloc());
    BlocScope.registerFactory<ChatBloc>(() => ChatBloc(WebSocketService()));
    BlocScope.registerFactory<FileUploadBloc>(() => FileUploadBloc());
    BlocScope.registerFactory<FormBloc>(() => FormBloc());
    BlocScope.registerFactory<WeatherBloc>(() => WeatherBloc());
    BlocScope.registerFactory<SettingsBloc>(() => SettingsBloc());
  }
}
