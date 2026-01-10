import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import '../bloc/bloc.dart';

/// A test utility class for testing Juice blocs.
///
/// BlocTester simplifies bloc testing by providing:
/// - Automatic stream emission tracking
/// - Convenient assertion methods
/// - Proper cleanup handling
///
/// ## Example
///
/// ```dart
/// test('increments counter', () async {
///   final bloc = CounterBloc();
///   final tester = BlocTester(bloc);
///
///   await tester.send(IncrementEvent());
///
///   tester.expectState((state) => state.count == 1);
///   tester.expectLastStatusIs<UpdatingStatus>();
///
///   await tester.dispose();
/// });
/// ```
class BlocTester<TBloc extends JuiceBloc<TState>, TState extends BlocState> {
  /// Creates a BlocTester for the given bloc.
  ///
  /// Automatically subscribes to the bloc's stream to track emissions.
  BlocTester(this.bloc) {
    _subscription = bloc.stream.listen(_emissions.add);
  }

  /// The bloc being tested.
  final TBloc bloc;

  /// All stream emissions captured during the test.
  List<StreamStatus<TState>> get emissions => List.unmodifiable(_emissions);

  final List<StreamStatus<TState>> _emissions = [];
  StreamSubscription<StreamStatus<TState>>? _subscription;

  /// Sends an event to the bloc and waits for processing.
  ///
  /// [event] - The event to send.
  /// [delay] - How long to wait for processing (default 10ms).
  Future<void> send(EventBase event, {Duration? delay}) async {
    await bloc.send(event);
    await Future.delayed(delay ?? const Duration(milliseconds: 10));
  }

  /// Sends an event and waits until a non-waiting status is emitted.
  ///
  /// Useful for testing async operations that go through waiting states.
  ///
  /// [event] - The event to send.
  /// [timeout] - Maximum time to wait (default 5 seconds).
  Future<StreamStatus<TState>> sendAndWaitForResult(
    EventBase event, {
    Duration timeout = const Duration(seconds: 5),
  }) async {
    final future =
        bloc.stream.firstWhere((s) => s is! WaitingStatus).timeout(timeout);
    await bloc.send(event);
    return await future;
  }

  /// The current state of the bloc.
  TState get state => bloc.state;

  /// The last emitted status, or null if none.
  StreamStatus<TState>? get lastStatus =>
      _emissions.isNotEmpty ? _emissions.last : null;

  /// The last emitted state, or the current bloc state if no emissions.
  TState get lastState => lastStatus?.state ?? bloc.state;

  // ============================================================
  // Assertions
  // ============================================================

  /// Asserts that the current state equals the expected state.
  void expectStateEquals(TState expected) {
    expect(bloc.state, equals(expected));
  }

  /// Asserts that the current state matches the predicate.
  void expectState(bool Function(TState state) predicate, [String? reason]) {
    expect(predicate(bloc.state), isTrue, reason: reason);
  }

  /// Asserts that the last emitted status is of the given type.
  void expectLastStatusIs<T extends StreamStatus>([String? reason]) {
    expect(lastStatus, isA<T>(), reason: reason);
  }

  /// Asserts that the emissions match the expected status type sequence.
  ///
  /// ```dart
  /// tester.expectStatusSequence([WaitingStatus, UpdatingStatus]);
  /// ```
  void expectStatusSequence(List<Type> expectedTypes, {int? skip}) {
    final emissions =
        skip != null ? _emissions.skip(skip).toList() : _emissions;

    expect(
      emissions.length,
      greaterThanOrEqualTo(expectedTypes.length),
      reason: 'Expected at least ${expectedTypes.length} emissions, '
          'got ${emissions.length}',
    );

    for (var i = 0; i < expectedTypes.length; i++) {
      final emission = emissions[i];
      final expectedType = expectedTypes[i];

      // Check using type matching to handle generics
      final matches = _matchesStatusType(emission, expectedType);
      expect(
        matches,
        isTrue,
        reason: 'Emission $i: expected $expectedType, '
            'got ${emission.runtimeType}',
      );
    }
  }

  /// Asserts that at least one emission matches the predicate.
  void expectAnyEmission(
    bool Function(StreamStatus<TState>) predicate, [
    String? reason,
  ]) {
    expect(
      _emissions.any(predicate),
      isTrue,
      reason: reason ?? 'No emission matched the predicate',
    );
  }

  /// Asserts that all emissions match the predicate.
  void expectAllEmissions(
    bool Function(StreamStatus<TState>) predicate, [
    String? reason,
  ]) {
    expect(
      _emissions.every(predicate),
      isTrue,
      reason: reason ?? 'Not all emissions matched the predicate',
    );
  }

  /// Asserts the number of emissions.
  void expectEmissionCount(int count, [String? reason]) {
    expect(_emissions.length, equals(count), reason: reason);
  }

  /// Asserts that a waiting status was emitted.
  void expectWasWaiting([String? reason]) {
    expectAnyEmission(
      (s) => s is WaitingStatus,
      reason ?? 'Expected a WaitingStatus emission',
    );
  }

  /// Asserts that a failure status was emitted.
  void expectWasFailure([String? reason]) {
    expectAnyEmission(
      (s) => s is FailureStatus,
      reason ?? 'Expected a FailureStatus emission',
    );
  }

  /// Asserts that no failure status was emitted.
  void expectNoFailure([String? reason]) {
    expect(
      _emissions.any((s) => s is FailureStatus),
      isFalse,
      reason: reason ?? 'Expected no FailureStatus emissions',
    );
  }

  // ============================================================
  // Utilities
  // ============================================================

  /// Checks if an emission matches a status type, handling generics.
  bool _matchesStatusType(StreamStatus emission, Type expectedType) {
    // Handle the base status types (without generics)
    if (expectedType == UpdatingStatus) {
      return emission is UpdatingStatus;
    } else if (expectedType == WaitingStatus) {
      return emission is WaitingStatus;
    } else if (expectedType == FailureStatus) {
      return emission is FailureStatus;
    } else if (expectedType == CancelingStatus) {
      return emission is CancelingStatus;
    }
    // Fall back to exact type match
    return emission.runtimeType == expectedType;
  }

  /// Clears all recorded emissions.
  void clearEmissions() {
    _emissions.clear();
  }

  /// Waits for a specific number of emissions.
  Future<void> waitForEmissions(int count, {Duration? timeout}) async {
    final completer = Completer<void>();
    final targetCount = _emissions.length + count;

    void check() {
      if (_emissions.length >= targetCount && !completer.isCompleted) {
        completer.complete();
      }
    }

    final sub = bloc.stream.listen((_) => check());

    try {
      await completer.future.timeout(
        timeout ?? const Duration(seconds: 5),
        onTimeout: () => throw TimeoutException(
          'Timed out waiting for $count emissions',
        ),
      );
    } finally {
      await sub.cancel();
    }
  }

  /// Disposes of the tester and closes the bloc.
  Future<void> dispose() async {
    await _subscription?.cancel();
    _subscription = null;
    await bloc.close();
  }
}

/// Extension to create a tester directly from a bloc.
extension BlocTesterExtension<TState extends BlocState> on JuiceBloc<TState> {
  /// Creates a BlocTester for this bloc.
  BlocTester<JuiceBloc<TState>, TState> tester() => BlocTester(this);
}
