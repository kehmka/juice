import 'package:juice/juice.dart';
import 'package:juice_observability/juice_observability.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // Console reporter so reports are visible with no backend. A real app adds a
  // Sentry/Crashlytics reporter to the list.
  BlocScope.register<ObservabilityBloc>(
    () => ObservabilityBloc.withConfig(
      ObservabilityConfig(
        reporters: [ConsoleCrashReporter()],
        maxBreadcrumbs: 10,
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
      title: 'juice_observability demo',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.red),
        useMaterial3: true,
      ),
      home: HomeScreen(),
    );
  }
}

class HomeScreen extends StatelessJuiceWidget<ObservabilityBloc> {
  HomeScreen({super.key}) : super(groups: {ObservabilityGroups.status});

  @override
  Widget onBuild(BuildContext context, StreamStatus status) {
    final s = bloc.state;
    return Scaffold(
      appBar: AppBar(title: const Text('juice_observability demo')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('${s.errorCount} errors · ${s.breadcrumbs.length} breadcrumbs'),
            if (s.lastError != null)
              Padding(
                padding: const EdgeInsets.all(8),
                child: Text('last: ${s.lastError}',
                    style: const TextStyle(color: Colors.red)),
              ),
            const SizedBox(height: 24),
            OutlinedButton(
              onPressed: () =>
                  bloc.breadcrumb('tapped at ${s.breadcrumbs.length}', category: 'ui'),
              child: const Text('Drop a breadcrumb'),
            ),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: () =>
                  bloc.recordError(StateError('demo error'), StackTrace.current),
              child: const Text('Record an error'),
            ),
            const SizedBox(height: 8),
            // An *uncaught* error — the installed FlutterError/PlatformDispatcher
            // handlers capture this automatically.
            TextButton(
              onPressed: () => Future<void>.error(StateError('uncaught async')),
              child: const Text('Throw uncaught (auto-captured)'),
            ),
          ],
        ),
      ),
    );
  }
}
