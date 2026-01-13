// ignore_for_file: avoid_print, must_be_immutable
import 'package:juice/juice.dart';

// --- State ---
class CounterState extends BlocState {
  final int count;

  const CounterState({this.count = 0});

  CounterState copyWith({int? count}) =>
      CounterState(count: count ?? this.count);
}

// --- Events ---
class IncrementEvent extends EventBase {}

class DecrementEvent extends EventBase {}

// --- Use Cases ---
class IncrementUseCase extends BlocUseCase<CounterBloc, IncrementEvent> {
  @override
  Future<void> execute(IncrementEvent event) async {
    emitUpdate(
      newState: bloc.state.copyWith(count: bloc.state.count + 1),
      groupsToRebuild: {'counter'},
    );
  }
}

class DecrementUseCase extends BlocUseCase<CounterBloc, DecrementEvent> {
  @override
  Future<void> execute(DecrementEvent event) async {
    emitUpdate(
      newState: bloc.state.copyWith(count: bloc.state.count - 1),
      groupsToRebuild: {'counter'},
    );
  }
}

// --- BLoC ---
class CounterBloc extends JuiceBloc<CounterState> {
  CounterBloc()
      : super(
          const CounterState(),
          [
            () => UseCaseBuilder(
                  typeOfEvent: IncrementEvent,
                  useCaseGenerator: () => IncrementUseCase(),
                ),
            () => UseCaseBuilder(
                  typeOfEvent: DecrementEvent,
                  useCaseGenerator: () => DecrementUseCase(),
                ),
          ],
        );
}

// --- Widget ---
class CounterWidget extends StatelessJuiceWidget<CounterBloc> {
  CounterWidget({super.key, super.groups = const {'counter'}});

  @override
  Widget onBuild(BuildContext context, StreamStatus status) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text('Count: ${bloc.state.count}',
            style: const TextStyle(fontSize: 24)),
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
  // Register bloc with BlocScope
  BlocScope.register<CounterBloc>(
    () => CounterBloc(),
    lifecycle: BlocLifecycle.permanent,
  );

  runApp(
    MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: const Text('Juice Counter')),
        body: Center(child: CounterWidget()),
      ),
    ),
  );
}
