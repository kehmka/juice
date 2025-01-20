import "package:juice/juice.dart";
import '../settings.dart';

class ToggleTemperatureUnitUseCase
    extends BlocUseCase<SettingsBloc, ToggleTemperatureUnitEvent> {
  @override
  Future<void> execute(ToggleTemperatureUnitEvent event) async {
    final currentState = bloc.state;
    emitUpdate(
      groupsToRebuild: const {"settings"},
      newState: currentState.copyWith(isCelsius: !currentState.isCelsius),
    );
  }
}
