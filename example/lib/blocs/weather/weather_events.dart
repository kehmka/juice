import "package:juice/juice.dart";

abstract class WeatherEvent extends EventBase {}

class FetchWeatherEvent extends WeatherEvent {
  final String city;

  FetchWeatherEvent({required this.city});
}
