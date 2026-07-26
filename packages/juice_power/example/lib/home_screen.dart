import 'package:juice/juice.dart';
import 'package:juice_power/juice_power.dart';

import 'demo_power_provider.dart';

/// Shows the three readings and, below them, one consumer's POLICY built from
/// them — the split this package exists to keep clean. The bloc reports; the
/// rule about what may run lives here, where the work is.
class HomeScreen extends StatelessJuiceWidget<PowerBloc> {
  HomeScreen({super.key, required this.demo}) : super(groups: PowerGroups.all);

  final DemoPowerProvider demo;

  /// This demo's policy: heavy work runs on power, or on a battery above 20%,
  /// unless the keeper asked the OS to conserve.
  bool _mayRunHeavyWork(PowerState s) {
    if (s.saverAsked) return false;
    if (s.isPluggedIn) return true;
    if (s.percent == null) return false; // unknown level → do not guess
    return !s.isAtOrBelow(20);
  }

  @override
  Widget onBuild(BuildContext context, StreamStatus status) {
    final s = bloc.state;
    final mayRun = _mayRunHeavyWork(s);

    return Scaffold(
      appBar: AppBar(title: const Text('juice_power')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _Row(label: 'status', value: s.status.name),
          _Row(
              label: 'plugged in',
              value: s.isPluggedIn ? 'yes' : 'no'),
          _Row(
              label: 'level',
              value: s.percent == null ? 'unknown' : '${s.percent}%'),
          _Row(
              label: 'power saver',
              value: s.saverOn == null ? 'unknown' : '${s.saverOn}'),
          const Divider(height: 32),
          Card(
            color: mayRun
                ? Colors.green.withValues(alpha: 0.15)
                : Colors.orange.withValues(alpha: 0.15),
            child: ListTile(
              title: Text(mayRun
                  ? 'Heavy work may run'
                  : 'Heavy work is paused'),
              subtitle: const Text(
                  'This rule lives in the app, not the package — only the app '
                  'knows what the work costs.'),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton(
              onPressed: demo.togglePlug,
              child: const Text('plug in / unplug')),
          const SizedBox(height: 8),
          FilledButton.tonal(
              onPressed: demo.toggleSaver,
              child: const Text('toggle power saver')),
          const SizedBox(height: 8),
          OutlinedButton(
              onPressed: demo.loseTheLevel,
              child: const Text('make the level unknown')),
          const SizedBox(height: 16),
          const Text(
            'The level drains one point every two seconds with NO status '
            'change, so what you see moving is the bloc polling.',
            style: TextStyle(fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label),
            Text(value,
                style: const TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
      );
}
