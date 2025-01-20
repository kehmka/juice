import "package:juice/juice.dart";
import 'settings.dart';
import 'use_cases/toggle_temp_unit_use_case.dart';

class SettingsBloc extends JuiceBloc<SettingsState> {
  SettingsBloc()
      : super(
          SettingsState(),
          [
            () => UseCaseBuilder(
                  typeOfEvent: ToggleTemperatureUnitEvent,
                  useCaseGenerator: () => ToggleTemperatureUnitUseCase(),
                ),
          ],
          [],
        );
}
