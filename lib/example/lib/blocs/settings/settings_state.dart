import 'package:juice/juice.dart';

class SettingsState extends BlocState {
  final bool isCelsius;

  SettingsState({this.isCelsius = true});

  SettingsState copyWith({bool? isCelsius}) {
    return SettingsState(
      isCelsius: isCelsius ?? this.isCelsius,
    );
  }
}
