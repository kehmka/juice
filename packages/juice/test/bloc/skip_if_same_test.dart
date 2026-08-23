import 'package:flutter_test/flutter_test.dart';
import 'package:juice/juice.dart';


/// `emitUpdate(skipIfSame: true)` — the ==-dedup emit option (BlocSignal
/// tee-up item 4, already in core). Per-CALL by design: a statement about
/// one emission site, never a bloc-wide mode — so `waiting → waiting`
/// refresh patterns and intentional re-emits are never silently swallowed.
/// These tests pin the real emitter behavior (the prior "coverage" only
/// mocked the parameter away).
class _RecordingLogger implements JuiceLogger {
  final skipped = <Map<String, dynamic>>[];
  @override
  void log(String m, {Level level = Level.info, Map<String, dynamic>? context}) {
    if (context?['type'] == 'state_emission_skipped') skipped.add(context!);
  }
  @override
  void logError(String m, Object e, StackTrace s, {Map<String, dynamic>? context}) {}
}

/// A state WITH value equality — the precondition `skipIfSame` documents.
/// Without `==`/`hashCode`, `newState == state` is identity-false and
/// dedup can never fire; that is a caller responsibility, not a core bug.
class _EqState extends BlocState {
  const _EqState(this.value);
  final int value;
  @override
  bool operator ==(Object other) => other is _EqState && other.value == value;
  @override
  int get hashCode => value.hashCode;
}

class _EmitSameEvent extends EventBase {
  _EmitSameEvent({required this.value, required this.skip});
  final int value;
  final bool skip;
  @override
  String toString() => 'EmitSame($value, skip:$skip)';
}

class _EmitSameUseCase extends BlocUseCase<_DedupBloc, _EmitSameEvent> {
  @override
  Future<void> execute(_EmitSameEvent event) async {
    emitUpdate(
      newState: _EqState(event.value),
      groupsToRebuild: {'g'},
      skipIfSame: event.skip,
    );
  }
}

class _DedupBloc extends JuiceBloc<_EqState> {
  _DedupBloc()
      : super(const _EqState(0), [
          () => UseCaseBuilder(
              typeOfEvent: _EmitSameEvent,
              useCaseGenerator: () => _EmitSameUseCase(),
              concurrency: EventConcurrency.sequential),
        ], []);
}

void main() {
  late _RecordingLogger logger;
  late _DedupBloc bloc;

  setUp(() {
    logger = _RecordingLogger();
    JuiceLoggerConfig.configureLogger(logger);
    bloc = _DedupBloc();
  });
  tearDown(() async {
    await bloc.close();
    JuiceLoggerConfig.configureLogger(DefaultJuiceLogger());
  });

  test('skipIfSame:true suppresses an equal-state emit and logs it', () async {
    final seen = <int>[];
    final sub = bloc.stream.listen((s) => seen.add(s.state.value));

    bloc.send(_EmitSameEvent(value: 1, skip: true)); // 0 -> 1: real change
    await Future<void>.delayed(const Duration(milliseconds: 30));
    bloc.send(_EmitSameEvent(value: 1, skip: true)); // 1 -> 1: skipped
    await Future<void>.delayed(const Duration(milliseconds: 30));

    expect(bloc.state.value, 1);
    expect(seen.where((v) => v == 1), hasLength(1),
        reason: 'the duplicate never reached the stream');
    expect(logger.skipped, hasLength(1));
    expect(logger.skipped.single['bloc'], '_DedupBloc');
    await sub.cancel();
  });

  test('skipIfSame:false (default) emits even when the state is unchanged',
      () async {
    var emits = 0;
    final sub = bloc.stream.listen((_) => emits++);

    bloc.send(_EmitSameEvent(value: 5, skip: false));
    await Future<void>.delayed(const Duration(milliseconds: 30));
    bloc.send(_EmitSameEvent(value: 5, skip: false)); // same value, still emits
    await Future<void>.delayed(const Duration(milliseconds: 30));

    expect(emits, greaterThanOrEqualTo(2),
        reason: 'default never dedups — intentional re-emits survive');
    expect(logger.skipped, isEmpty);
    await sub.cancel();
  });

  test('skipIfSame:true still emits when the state actually changed', () async {
    final seen = <int>[];
    final sub = bloc.stream.listen((s) => seen.add(s.state.value));

    bloc.send(_EmitSameEvent(value: 1, skip: true));
    bloc.send(_EmitSameEvent(value: 2, skip: true));
    await Future<void>.delayed(const Duration(milliseconds: 40));

    expect(seen.contains(1), isTrue);
    expect(seen.contains(2), isTrue);
    expect(logger.skipped, isEmpty, reason: 'each was a real change');
    await sub.cancel();
  });
}
