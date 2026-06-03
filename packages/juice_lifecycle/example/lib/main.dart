import 'package:juice/juice.dart';
import 'package:juice_lifecycle/juice_lifecycle.dart';

import 'demo_lifecycle_provider.dart';
import 'home_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // Demo provider so transitions show without backgrounding the app. Swap for
  // LifecycleConfig() (default WidgetsLifecycleProvider) in a real app.
  BlocScope.register<LifecycleBloc>(
    () => LifecycleBloc.withConfig(
      LifecycleConfig(provider: DemoLifecycleProvider()),
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
      title: 'juice_lifecycle demo',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.orange),
        useMaterial3: true,
      ),
      home: HomeScreen(),
    );
  }
}
