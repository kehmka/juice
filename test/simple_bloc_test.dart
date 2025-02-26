import 'package:flutter_test/flutter_test.dart';
import 'package:juice/juice.dart';

class TestState extends BlocState {
  final int value;
  
  TestState({required this.value});
  
  TestState copyWith({int? value}) => 
    TestState(value: value ?? this.value);
}

class TestEvent extends EventBase {}

class IncrementUseCase extends BlocUseCase<TestBloc, TestEvent> {
  @override
  Future<void> execute(TestEvent event) async {
    final newState = bloc.state.copyWith(value: bloc.state.value + 1);
    emitUpdate(newState: newState, groupsToRebuild: {"test-group"});
  }
}

class TestBloc extends JuiceBloc<TestState> {
  TestBloc()
    : super(
        TestState(value: 0), 
        [
          () => UseCaseBuilder(
            typeOfEvent: TestEvent,
            useCaseGenerator: () => IncrementUseCase(),
          ),
        ], 
        [],
      );
}

void main() {
  group('Basic Juice Framework Tests', () {
    late TestBloc bloc;

    setUp(() {
      bloc = TestBloc();
    });

    tearDown(() {
      bloc.close();
    });

    test('Bloc initializes with correct state', () {
      expect(bloc.state.value, 0);
    });

    test('Sending event updates state correctly', () async {
      // Send event
      await bloc.send(TestEvent());
      
      // Verify state updated
      expect(bloc.state.value, 1);
    });
  });
}