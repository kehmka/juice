// ignore_for_file: must_be_immutable, deprecated_member_use_from_same_package

import 'package:juice/juice.dart';

// Test State
class TestState extends BlocState {
  final int value;

  TestState({required this.value});

  TestState copyWith({int? value}) => TestState(value: value ?? this.value);

  @override
  String toString() => 'TestState(value: $value)';
}

// Test Events
class TestEvent extends EventBase {
  TestEvent({Set<String>? groups}) {
    if (groups != null) {
      groupsToRebuild = groups;
    }
  }
}

class IncrementEvent extends TestEvent {
  IncrementEvent({super.groups});
}

class DecrementEvent extends TestEvent {
  DecrementEvent({super.groups});
}

// Test Use Case
class TestUseCase extends BlocUseCase<TestBloc, TestEvent> {
  @override
  Future<void> execute(TestEvent event) async {
    debugPrint("executing TestUseCase");
    final newState = bloc.state.copyWith(value: bloc.state.value + 1);
    emitUpdate(newState: newState, groupsToRebuild: {"test-group"});
  }
}

class IncrementUseCase extends BlocUseCase<TestBloc, IncrementEvent> {
  @override
  Future<void> execute(IncrementEvent event) async {
    final newState = bloc.state.copyWith(value: bloc.state.value + 1);
    emitUpdate(newState: newState, groupsToRebuild: {"test-group"});
  }
}

class DecrementUseCase extends BlocUseCase<TestBloc, DecrementEvent> {
  @override
  Future<void> execute(DecrementEvent event) async {
    final newState = bloc.state.copyWith(value: bloc.state.value - 1);
    emitUpdate(newState: newState, groupsToRebuild: {"test-group"});
  }
}

// Test Bloc
class TestBloc extends JuiceBloc<TestState> {
  TestBloc({required TestState initialState})
      : super(
          initialState,
          [
            () => UseCaseBuilder(
                  typeOfEvent: TestEvent,
                  useCaseGenerator: () => TestUseCase(),
                ),
            () => UseCaseBuilder(
                  typeOfEvent: IncrementEvent,
                  useCaseGenerator: () => IncrementUseCase(),
                ),
            () => UseCaseBuilder(
                  typeOfEvent: DecrementEvent,
                  useCaseGenerator: () => DecrementUseCase(),
                ),
          ],
          [],
        );
}

// Test Resolver
class TestResolver implements BlocDependencyResolver {
  final Map<Type, JuiceBloc> _blocs = {};

  TestResolver({Map<Type, JuiceBloc>? blocs}) {
    if (blocs != null) {
      _blocs.addAll(blocs);
    }
  }

  @override
  T resolve<T extends JuiceBloc<BlocState>>({Map<String, dynamic>? args}) {
    if (!_blocs.containsKey(T)) {
      if (T == TestBloc) {
        _blocs[T] = TestBloc(initialState: TestState(value: 0)) as JuiceBloc;
      } else {
        throw Exception('No bloc of type $T is registered');
      }
    }
    return _blocs[T] as T;
  }

  @override
  BlocLease<T> lease<T extends JuiceBloc<BlocState>>({Object? scope}) {
    final bloc = resolve<T>();
    return BlocLease<T>(bloc, () {});
  }

  void dispose<T extends JuiceBloc>() {
    if (_blocs.containsKey(T)) {
      _blocs[T]!.close();
      _blocs.remove(T);
    }
  }

  @override
  Future<void> disposeAll() async {
    for (var bloc in _blocs.values) {
      await bloc.close();
    }
    _blocs.clear();
  }
}

// Test Widget using BlocScope (pure Juice pattern)
class TestWidget extends StatelessJuiceWidget<TestBloc> {
  TestWidget({
    super.key,
    super.groups = const {"test-group"},
    this.doOnBuild = _noop,
  });

  final Function doOnBuild;

  static void _noop() {}

  @override
  Widget onBuild(BuildContext context, StreamStatus status) {
    debugPrint("Executing onBuild");
    doOnBuild();
    return Text('Value: ${bloc.state.value}');
  }
}

// Second Test Bloc and related classes for testing widgets that depend on multiple blocs
class SecondTestState extends BlocState {
  final String status;

  SecondTestState({required this.status});

  SecondTestState copyWith({String? status}) =>
      SecondTestState(status: status ?? this.status);

  @override
  String toString() => 'SecondTestState(status: $status)';
}

class SecondTestEvent extends EventBase {}

class SecondTestBloc extends JuiceBloc<SecondTestState> {
  SecondTestBloc({required SecondTestState initialState})
      : super(initialState, [], []);

  void updateStatus(String newStatus) {
    send(UpdateEvent(
      newState: state.copyWith(status: newStatus),
      groupsToRebuild: {"status-group"},
    ));
  }
}

// For testing relays between blocs
class RelayTestUseCase extends BlocUseCase<TestBloc, TestEvent> {
  late SecondTestBloc targetBloc;

  @override
  Future<void> execute(TestEvent event) async {
    // Update own state
    final newState = bloc.state.copyWith(value: bloc.state.value + 1);
    emitUpdate(newState: newState, groupsToRebuild: {"test-group"});

    // Update target bloc's state
    targetBloc.updateStatus('Updated from relay: ${newState.value}');
  }
}
