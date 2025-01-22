import "package:juice/juice.dart";

abstract class SettingsEvent extends EventBase {}

class ToggleTemperatureUnitEvent extends SettingsEvent {}
