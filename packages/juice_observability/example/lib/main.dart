import 'dart:developer' as developer;

import 'package:juice/juice.dart';
import 'package:juice_observability/juice_observability.dart';

import 'telemetry_feed.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // The in-app telemetry feed — a Juice-pure consumer of the same events
  // the mirror posts to DevTools, so the demo shows the mirror working
  // without DevTools open (see telemetry_feed.dart for the self-loop guard).
  BlocScope.register<TelemetryFeedBloc>(() => TelemetryFeedBloc(),
      lifecycle: BlocLifecycle.permanent);

  // Mirror Juice's structured log entries (use-case runs + completions,
  // emissions, bloc lifecycle, leaks, errors) to the VM's extension-event
  // stream as `juice:<type>` events — live in DevTools and any VM-service
  // listener. A decorator: console logging keeps working underneath. The
  // `post` seam is injectable: here it TEES — the real VM post, plus the
  // in-app feed (filtered so the feed never consumes its own telemetry).
  JuiceLoggerConfig.configureLogger(DevtoolsJuiceLogger(
    post: (kind, data) {
      developer.postEvent(kind, data);
      if (!isSelfTelemetry(data)) {
        BlocScope.get<TelemetryFeedBloc>().append(telemetryLine(kind, data));
      }
    },
  ));

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
            const SizedBox(height: 24),
            // Every tap above runs a use case; its start/end pair — same
            // executionId, elapsed on the end — lands here within a frame.
            Expanded(child: TelemetryPanel()),
          ],
        ),
      ),
    );
  }
}

/// The rolling feed of `juice:<type>` events, newest at the bottom.
class TelemetryPanel extends StatelessJuiceWidget<TelemetryFeedBloc> {
  TelemetryPanel({super.key}) : super(groups: TelemetryFeedGroups.all);

  @override
  Widget onBuild(BuildContext context, StreamStatus status) {
    final lines = bloc.state.lines;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('DevTools mirror — live juice: events',
              style: Theme.of(context).textTheme.labelSmall),
          const SizedBox(height: 6),
          Expanded(
            child: lines.isEmpty
                ? const Text('tap a button above')
                : ListView(
                    children: [
                      for (final l in lines)
                        Text(l,
                            style: const TextStyle(
                                fontFamily: 'monospace', fontSize: 11)),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}
