import 'package:juice/juice.dart';
import '../../blocs.dart';

class WeatherDashboard extends StatefulWidget {
  const WeatherDashboard({super.key});

  @override
  WeatherDashboardState createState() => WeatherDashboardState();
}

class WeatherDashboardState
    extends JuiceWidgetState2<WeatherBloc, SettingsBloc, WeatherDashboard>
    with SingleTickerProviderStateMixin {
  WeatherDashboardState() : super(groups: {"weather", "settings"});

  late AnimationController _animationController;

  @override
  void onInit() {
    super.onInit();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget onBuild(BuildContext context, StreamStatus status) {
    final weatherState = bloc1.state;
    final settingsState = bloc2.state;

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  onSubmitted: (value) {
                    if (value.isNotEmpty) {
                      bloc1.send(FetchWeatherEvent(city: value));
                    }
                  },
                  decoration: const InputDecoration(
                    hintText: "Enter city name",
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              ElevatedButton(
                onPressed: () => bloc2.send(ToggleTemperatureUnitEvent()),
                child: Text(
                  settingsState.isCelsius ? "Switch to °F" : "Switch to °C",
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (weatherState.isLoading)
            const Center(child: CircularProgressIndicator()),
          if (!weatherState.isLoading && weatherState.currentWeather != null)
            _buildCurrentWeather(weatherState.currentCity!,
                weatherState.currentWeather!, settingsState.isCelsius),
          const SizedBox(height: 16),
          if (!weatherState.isLoading && weatherState.forecast.isNotEmpty)
            _buildForecast(weatherState.forecast, settingsState.isCelsius),
        ],
      ),
    );
  }

  Widget _buildCurrentWeather(
      String city, Map<String, dynamic> weather, bool isCelsius) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          "Current Weather in $city",
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Text(
              weather["icon"],
              style: const TextStyle(fontSize: 32),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _convertTemperature(weather["temperature"], isCelsius),
                  style: const TextStyle(fontSize: 24),
                ),
                Text(weather["conditions"]),
              ],
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildForecast(List<Map<String, dynamic>> forecast, bool isCelsius) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          "5-Day Forecast",
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Column(
          children: forecast.map((day) {
            return Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(day["day"]),
                Row(
                  children: [
                    Text(day["icon"]),
                    const SizedBox(width: 8),
                    Text(_convertTemperature(day["temperature"], isCelsius)),
                    const SizedBox(width: 8),
                    Text(day["conditions"]),
                  ],
                ),
              ],
            );
          }).toList(),
        ),
      ],
    );
  }

  String _convertTemperature(String temp, bool isCelsius) {
    final numericValue = int.tryParse(temp.replaceAll("°C", "").trim()) ?? 0;
    if (isCelsius) {
      return "$numericValue°C";
    } else {
      final fahrenheit = (numericValue * 9 / 5 + 32).round();
      return "$fahrenheit°F";
    }
  }
}
