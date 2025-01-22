import 'package:flutter_test/flutter_test.dart';
import '../lib/blocs/blocs.dart';

void main() {
  group('CounterBloc Tests', () {
    late CounterBloc bloc;

    setUp(() {
      // Initialize the CounterBloc before each test
      bloc = CounterBloc();
    });

    tearDown(() {
      // Close the bloc after each test to clean up resources
      bloc.close();
    });

    test('Initial state is CounterState(count: 0)', () {
      expect(bloc.state.count, 0);
    });

    test('IncrementEvent increments the count', () async {
      // Dispatch IncrementEvent
      await bloc.send(IncrementEvent());

      // Verify the updated state
      expect(bloc.state.count, 1);
    });

    test('DecrementEvent decrements the count', () async {
      // Increment twice first
      await bloc.send(IncrementEvent());
      await bloc.send(IncrementEvent());
      await bloc.send(IncrementEvent());

      // Dispatch DecrementEvent
      await bloc.send(DecrementEvent());

      // Verify the updated state
      expect(bloc.state.count, 2);
    });

    test('ResetEvent resets the count to 0', () async {
      // Increment first
      await bloc.send(IncrementEvent());

      // Dispatch ResetEvent
      await bloc.send(ResetEvent());

      // Verify the updated state
      expect(bloc.state.count, 0);
    });
  });
}
