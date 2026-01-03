import 'dart:math';
import "package:juice/juice.dart";
import '../weather.dart';

class FetchWeatherUseCase extends BlocUseCase<WeatherBloc, FetchWeatherEvent> {
  @override
  Future<void> execute(FetchWeatherEvent event) async {
    emitUpdate(
      groupsToRebuild: const {"weather"},
      newState: bloc.state.copyWith(isLoading: true, currentCity: event.city),
    );

    // Simulate an API call with a delay
    await Future.delayed(const Duration(seconds: 2));

    // Mocked weather data
    final random = Random();
    final weatherData = {
      "temperature": "${random.nextInt(30) + 10}°C",
      "conditions": "Sunny",
      "icon": "☀️",
    };
    final forecastData = List.generate(5, (index) {
      return {
        "day": "Day ${index + 1}",
        "temperature": "${random.nextInt(20) + 10}°C",
        "conditions": index % 2 == 0 ? "Cloudy" : "Clear",
        "icon": index % 2 == 0 ? "☁️" : "🌤️",
      };
    });

    emitUpdate(
      groupsToRebuild: const {"weather"},
      newState: bloc.state.copyWith(
        isLoading: false,
        currentWeather: weatherData,
        forecast: forecastData,
      ),
    );
  }
}
