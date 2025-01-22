import 'package:juice/juice.dart';
import 'package:juice/example/lib/blocs/blocs.dart';

class CounterWidget extends StatelessJuiceWidget<CounterBloc> {
  CounterWidget({super.key, super.groups = const {"counter"}});

  @override
  Widget onBuild(BuildContext context, StreamStatus status) {
    // Using match without specifying the return type
    return status.match<CounterState, Widget>(
      updating: (_) => Text(
        'Count: ${bloc.state.count}',
        style: const TextStyle(fontSize: 32),
      ),
      waiting: (_) => Text("Waiting for the counter to reply"),
      failure: (_) => Text("The counter failed to count"),
      canceling: (_) => Text("The counter canceled the count"),
      orElse: (_) => Text("Unknown where the counter is"),
    );
  }
}

class CounterButtons extends StatelessJuiceWidget<CounterBloc> {
  CounterButtons({super.key, super.groups = optOutOfRebuilds});

  @override
  Widget onBuild(BuildContext context, StreamStatus status) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        ElevatedButton(
          onPressed: () => bloc.send(IncrementEvent()),
          child: const Text('+'),
        ),
        const SizedBox(width: 16),
        ElevatedButton(
          onPressed: () => bloc.send(DecrementEvent()),
          child: const Text('-'),
        ),
        const SizedBox(width: 16),
        ElevatedButton(
          onPressed: () => bloc.send(ResetEvent()),
          child: const Text('Reset'),
        ),
      ],
    );
  }
}
