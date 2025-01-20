import "package:juice/juice.dart";
import 'use_cases/fetch_weather_use_case.dart';
import 'weather.dart';

class WeatherBloc extends JuiceBloc<WeatherState> {
  WeatherBloc()
      : super(
          WeatherState(),
          [
            () => UseCaseBuilder(
                  typeOfEvent: FetchWeatherEvent,
                  useCaseGenerator: () => FetchWeatherUseCase(),
                ),
          ],
          [],
        );
}
