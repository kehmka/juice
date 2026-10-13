/// Testing utilities for Juice blocs.
///
/// - [juiceTest] / [runJuiceTest]: declare a bloc test — build, seed, act,
///   then assert on exactly what the bloc emitted (groups as widgets saw
///   them), with the bloc closed before asserting and every use-case or
///   stream-binding error reported. The default.
/// - [BlocTester]: an imperative recorder with assertion helpers.
///
/// ```dart
/// import 'package:juice/testing.dart';
///
/// juiceTest<CounterBloc, CounterState>(
///   'increment emits the new count',
///   build: () => CounterBloc(),
///   act: (bloc) => bloc.send(IncrementEvent()),
///   expect: () => [isUpdatingStatus(state: const CounterState(count: 1))],
/// );
/// ```
library testing;

export 'src/testing/testing.dart';
