/// Testing utilities for Juice blocs.
///
/// This library provides helpers for testing Juice blocs including:
/// - [BlocTester] for simplified bloc testing with assertions
///
/// ## Usage
///
/// ```dart
/// import 'package:juice/testing.dart';
///
/// void main() {
///   test('counter increments', () async {
///     final bloc = CounterBloc();
///     final tester = BlocTester(bloc);
///
///     await tester.send(IncrementEvent());
///
///     tester.expectState((s) => s.count == 1);
///     tester.expectLastStatusIs<UpdatingStatus>();
///
///     await tester.dispose();
///   });
/// }
/// ```
library testing;

export 'src/testing/testing.dart';
