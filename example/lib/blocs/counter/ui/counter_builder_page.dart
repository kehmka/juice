import 'package:juice/juice.dart';
import '../counter_bloc.dart';
import '../counter_events.dart';

/// Counter example using the new JuiceBuilder pattern.
///
/// This demonstrates the composable, inline approach to building
/// reactive widgets without requiring inheritance.
class CounterBuilderPage extends StatelessWidget {
  const CounterBuilderPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Counter (Builder Pattern)')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // JuiceBuilder - inline, composable, no inheritance needed
            JuiceBuilder<CounterBloc>(
              groups: const {'counter'},
              builder: (context, bloc, status) {
                return Text(
                  'Count: ${bloc.state.count}',
                  style: const TextStyle(fontSize: 32),
                );
              },
            ),
            const SizedBox(height: 24),

            // Status indicator using buildWhen for conditional rebuilds
            JuiceBuilder<CounterBloc>(
              groups: const {'counter'},
              buildWhen: (status) => status is WaitingStatus || status is UpdatingStatus,
              builder: (context, bloc, status) {
                if (status is WaitingStatus) {
                  return const CircularProgressIndicator();
                }
                return const SizedBox.shrink();
              },
            ),
          ],
        ),
      ),
      floatingActionButton: const CounterButtonsBuilder(),
    );
  }
}

/// Buttons that don't need to rebuild when state changes.
/// Uses optOutOfRebuilds to prevent unnecessary rebuilds.
class CounterButtonsBuilder extends StatelessWidget {
  const CounterButtonsBuilder({super.key});

  @override
  Widget build(BuildContext context) {
    // Using JuiceBuilder with optOutOfRebuilds - buttons never rebuild
    // but still have access to the bloc for sending events
    return JuiceBuilder<CounterBloc>(
      groups: optOutOfRebuilds,
      builder: (context, bloc, status) {
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            FloatingActionButton(
              heroTag: 'increment',
              onPressed: () => bloc.send(IncrementEvent()),
              child: const Icon(Icons.add),
            ),
            const SizedBox(width: 16),
            FloatingActionButton(
              heroTag: 'decrement',
              onPressed: () => bloc.send(DecrementEvent()),
              child: const Icon(Icons.remove),
            ),
            const SizedBox(width: 16),
            FloatingActionButton(
              heroTag: 'reset',
              onPressed: () => bloc.send(ResetEvent()),
              child: const Icon(Icons.refresh),
            ),
          ],
        );
      },
    );
  }
}

/// Example showing JuiceBuilder with local state.
///
/// When you need local widget state, simply use a StatefulWidget
/// and put the JuiceBuilder inside - no special mixin needed.
class CounterWithLocalState extends StatefulWidget {
  const CounterWithLocalState({super.key});

  @override
  State<CounterWithLocalState> createState() => _CounterWithLocalStateState();
}

class _CounterWithLocalStateState extends State<CounterWithLocalState> {
  int _multiplier = 1;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Local state controls
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('Multiplier: '),
            DropdownButton<int>(
              value: _multiplier,
              items: [1, 2, 5, 10]
                  .map((v) => DropdownMenuItem(value: v, child: Text('$v')))
                  .toList(),
              onChanged: (v) => setState(() => _multiplier = v ?? 1),
            ),
          ],
        ),
        const SizedBox(height: 16),

        // JuiceBuilder combines local state with bloc state
        JuiceBuilder<CounterBloc>(
          groups: const {'counter'},
          builder: (context, bloc, status) {
            final adjustedCount = bloc.state.count * _multiplier;
            return Text(
              'Adjusted Count: $adjustedCount',
              style: const TextStyle(fontSize: 24),
            );
          },
        ),
      ],
    );
  }
}
