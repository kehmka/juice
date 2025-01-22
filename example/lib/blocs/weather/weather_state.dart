import 'package:juice/juice.dart';

class WeatherState extends BlocState {
  final bool isLoading;
  final String? currentCity;
  final Map<String, dynamic>? currentWeather;
  final List<Map<String, dynamic>> forecast;

  WeatherState({
    this.isLoading = false,
    this.currentCity,
    this.currentWeather,
    this.forecast = const [],
  });

  WeatherState copyWith({
    bool? isLoading,
    String? currentCity,
    Map<String, dynamic>? currentWeather,
    List<Map<String, dynamic>>? forecast,
  }) {
    return WeatherState(
      isLoading: isLoading ?? this.isLoading,
      currentCity: currentCity ?? this.currentCity,
      currentWeather: currentWeather ?? this.currentWeather,
      forecast: forecast ?? this.forecast,
    );
  }
}
