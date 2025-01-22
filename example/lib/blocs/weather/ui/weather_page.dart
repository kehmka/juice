import 'package:flutter/material.dart';
import 'weather_dashboard.dart';

class WeatherPage extends StatelessWidget {
  const WeatherPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Weather Dashboard"),
      ),
      body: const WeatherDashboard(),
    );
  }
}
