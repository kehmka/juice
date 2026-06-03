import 'package:juice/juice.dart';
import 'package:juice_permissions/juice_permissions.dart';

import 'demo_permission_provider.dart';
import 'home_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // Demo provider so the app runs with no device/OS prompts. Swap for
  // PermissionsConfig() (default PermissionHandlerProvider) in a real app.
  BlocScope.register<PermissionsBloc>(
    () => PermissionsBloc.withConfig(
      PermissionsConfig(
        provider: DemoPermissionProvider(
          denyPermanently: {JuicePermission.notification},
        ),
      ),
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
      title: 'juice_permissions demo',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
      ),
      home: HomeScreen(),
    );
  }
}
