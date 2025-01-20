import 'package:juice/juice.dart';
import 'package:juice/example/lib/blocs/blocs.dart';

class CounterWidget extends StatelessJuiceWidget<CounterBloc> {
  CounterWidget({super.key, super.groups = const {"counter"}});

  @override
  Widget onBuild(BuildContext context, StreamStatus status) {
    return Text(
      'Count: ${bloc.state.count}',
      style: const TextStyle(fontSize: 32),
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
