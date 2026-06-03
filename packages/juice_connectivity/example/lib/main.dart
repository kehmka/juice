import 'package:juice/juice.dart';
import 'package:juice_connectivity/juice_connectivity.dart';

import 'demo_connectivity_provider.dart';
import 'home_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // Demo provider so the app runs with no device/network. Swap for
  // ConnectivityConfig() (default ConnectivityPlusProvider) in a real app.
  BlocScope.register<ConnectivityBloc>(
    () => ConnectivityBloc.withConfig(
      ConnectivityConfig(provider: DemoConnectivityProvider()),
    ),
    lifecycle: BlocLifecycle.permanent,
  );

  runApp(const DemoApp());
}

class DemoApp extends StatelessWidget {
  const DemoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'juice_connectivity demo',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
        useMaterial3: true,
      ),
      home: HomeScreen(),
    );
  }
}
