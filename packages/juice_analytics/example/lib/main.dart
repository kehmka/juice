import 'package:juice/juice.dart';
import 'package:juice_analytics/juice_analytics.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // Console sink so events are visible with no backend. A real app adds a
  // vendor sink (Firebase/Mixpanel/…) to the list.
  BlocScope.register<AnalyticsBloc>(
    () => AnalyticsBloc.withConfig(
      AnalyticsConfig(sinks: [ConsoleAnalyticsSink()], initiallyEnabled: false),
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
      title: 'juice_analytics demo',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.cyan),
        useMaterial3: true,
      ),
      home: HomeScreen(),
    );
  }
}

class HomeScreen extends StatelessJuiceWidget<AnalyticsBloc> {
  HomeScreen({super.key}) : super(groups: {AnalyticsGroups.status});

  @override
  Widget onBuild(BuildContext context, StreamStatus status) {
    final s = bloc.state;
    return Scaffold(
      appBar: AppBar(title: const Text('juice_analytics demo')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SwitchListTile(
              title: const Text('Tracking consent'),
              value: s.enabled,
              onChanged: bloc.setConsent,
            ),
            const SizedBox(height: 12),
            Text('${s.eventCount} sent · ${s.droppedCount} dropped (no consent)'),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: () => bloc.log('button_tapped', {'at': 'demo'}),
              child: const Text('Log an event'),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: () => bloc.screen('Demo'),
              child: const Text('Track screen view'),
            ),
          ],
        ),
      ),
    );
  }
}
