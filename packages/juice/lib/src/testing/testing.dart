/// Testing utilities for Juice blocs.
///
/// This library provides helpers for testing Juice blocs including:
/// - [juiceTest] for one bloc: build, act, assert on exactly what it emitted
/// - [juiceFlowTest] for several blocs and the reactions between them
/// - [BlocTester] for simplified bloc testing with assertions
///
/// Import this in your test files:
/// ```dart
/// import 'package:juice/testing.dart';
/// ```
library testing;

export 'bloc_tester.dart';
export 'juice_flow.dart';
export 'juice_test.dart' hide asEmissionsMatcher;
