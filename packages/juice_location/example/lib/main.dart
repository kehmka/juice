import 'package:juice/juice.dart';
import 'package:juice_location/juice_location.dart';

import 'demo_location_source.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // Demo source so the app runs with no GPS. Swap for LocationConfig()
  // (default GeolocatorLocationSource) in a real app.
  BlocScope.register<LocationBloc>(
    () => LocationBloc.withConfig(
      LocationConfig(source: DemoLocationSource()),
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
      title: 'juice_location demo',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.green),
        useMaterial3: true,
      ),
      home: HomeScreen(),
    );
  }
}

class HomeScreen extends StatelessJuiceWidget<LocationBloc> {
  HomeScreen({super.key}) : super(groups: LocationGroups.all);

  @override
  Widget onBuild(BuildContext context, StreamStatus status) {
    final state = bloc.state;
    final p = state.current;

    return Scaffold(
      appBar: AppBar(title: const Text('juice_location demo')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.location_on, size: 72, color: Colors.green),
            const SizedBox(height: 12),
            Text(
              p == null
                  ? 'No fix yet'
                  : '${p.latitude.toStringAsFixed(5)}, '
                      '${p.longitude.toStringAsFixed(5)}',
              key: const Key('position'),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            if (state.lastError != null)
              Text('Error: ${state.lastError}',
                  style: const TextStyle(color: Colors.red)),
            const SizedBox(height: 24),
            Wrap(
              spacing: 12,
              children: [
                FilledButton(
                  onPressed: bloc.getCurrent,
                  child: const Text('Get current'),
                ),
                state.tracking
                    ? OutlinedButton(
                        onPressed: bloc.stopTrackingUpdates,
                        child: const Text('Stop tracking'),
                      )
                    : FilledButton.tonal(
                        onPressed: bloc.startTrackingUpdates,
                        child: const Text('Start tracking'),
                      ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
