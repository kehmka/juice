import 'package:flutter_test/flutter_test.dart';
import 'package:juice/juice.dart';
import 'package:juice_power/juice_power.dart';
import 'package:juice_power_example/demo_power_provider.dart';
import 'package:juice_power_example/home_screen.dart';

/// Smoke test: the demo seam drives the bloc and the screen renders both the
/// readings and the consumer-side gate built from them.
void main() {
  testWidgets('the demo renders and reacts to the cable', (tester) async {
    final demo = DemoPowerProvider();
    BlocScope.register<PowerBloc>(
      () => PowerBloc.withConfig(
          PowerConfig(provider: demo, pollInterval: Duration.zero)),
      lifecycle: BlocLifecycle.permanent,
    );

    await tester.pumpWidget(MaterialApp(home: HomeScreen(demo: demo)));
    await tester.pump(const Duration(milliseconds: 50));

    // Starts on battery at 62% — above the demo's 20% floor, so work may run.
    expect(find.text('Heavy work may run'), findsOneWidget);

    demo.toggleSaver();
    await tester.pump(const Duration(milliseconds: 50));

    // The keeper asked the OS to conserve; that outranks a healthy battery.
    expect(find.text('Heavy work is paused'), findsOneWidget);

    await demo.dispose();
  });
}
