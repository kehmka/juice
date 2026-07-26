import 'package:juice/juice.dart';
import 'package:juice_power/juice_power.dart';

import 'demo_power_provider.dart';
import 'home_screen.dart';

final demo = DemoPowerProvider();

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // Demo provider so the app runs with no device. Swap for PowerConfig()
  // (default BatteryPlusProvider) in a real app.
  BlocScope.register<PowerBloc>(
    () => PowerBloc.withConfig(PowerConfig(
      provider: demo,
      pollInterval: const Duration(seconds: 1),
    )),
    lifecycle: BlocLifecycle.permanent,
  );

  runApp(const DemoApp());
}

class DemoApp extends StatelessWidget {
  const DemoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'juice_power demo',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.amber),
        useMaterial3: true,
      ),
      home: HomeScreen(demo: demo),
    );
  }
}
