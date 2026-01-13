// ignore_for_file: avoid_print
import 'package:flutter/material.dart';
import 'package:juice/juice.dart';

// --- State ---
class CounterState {
  const CounterState({this.count = 0});
  final int count;

  CounterState copyWith({int? count}) =>
      CounterState(count: count ?? this.count);
}

// --- Events ---
class IncrementEvent extends EventBase {}

class DecrementEvent extends EventBase {}

// --- Use Cases ---
class IncrementUseCase extends UseCase<CounterBloc, CounterState, IncrementEvent> {
  @override
  Future<void> execute(ctx, event) async {
    ctx.emit(ctx.state.copyWith(count: ctx.state.count + 1));
  }
}

class DecrementUseCase extends UseCase<CounterBloc, CounterState, DecrementEvent> {
  @override
  Future<void> execute(ctx, event) async {
    ctx.emit(ctx.state.copyWith(count: ctx.state.count - 1));
  }
}

// --- BLoC ---
class CounterBloc extends JuiceBloc<CounterState> {
  CounterBloc()
      : super(
          initialState: const CounterState(),
          useCaseBuilders: [
            () => UseCaseBuilder<IncrementEvent>(
                  typeOfEvent: IncrementEvent,
                  useCaseGenerator: () => IncrementUseCase(),
                ),
            () => UseCaseBuilder<DecrementEvent>(
                  typeOfEvent: DecrementEvent,
                  useCaseGenerator: () => DecrementUseCase(),
                ),
          ],
        );
}

// --- Widget ---
class CounterWidget extends StatelessJuiceWidget<CounterBloc> {
  CounterWidget({super.key});

  @override
  CounterBloc createBloc() => CounterBloc();

  @override
  Widget onBuild(BuildContext context, StreamStatus<CounterState> status) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text('Count: ${bloc.state.count}', style: const TextStyle(fontSize: 24)),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ElevatedButton(
              onPressed: () => bloc.send(DecrementEvent()),
              child: const Text('-'),
            ),
            const SizedBox(width: 16),
            ElevatedButton(
              onPressed: () => bloc.send(IncrementEvent()),
              child: const Text('+'),
            ),
          ],
        ),
      ],
    );
  }
}

// --- App ---
void main() {
  runApp(
    MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: const Text('Juice Counter Example')),
        body: Center(child: CounterWidget()),
      ),
    ),
  );
}
