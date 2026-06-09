import 'package:flutter_test/flutter_test.dart';
import 'package:juice/juice.dart';

// State: a log of appended values + a counter of how many "drop" runs executed.
class RaceState extends BlocState {
  final List<int> log;
  final int runs;
  const RaceState({this.log = const [], this.runs = 0});
  RaceState copyWith({List<int>? log, int? runs}) =>
      RaceState(log: log ?? this.log, runs: runs ?? this.runs);
}

class SeqEvent extends EventBase {
  final int n;
  SeqEvent(this.n);
}

class ConcEvent extends EventBase {
  final int n;
  ConcEvent(this.n);
}

class DropEvent extends EventBase {}

/// The race shape: read a snapshot of state BEFORE an await, append AFTER.
/// Under `concurrent` this clobbers; under `sequential` it's ordered + safe.
class _AppendUseCase<E extends EventBase> extends BlocUseCase<RaceBloc, E> {
  final int Function(E) pick;
  _AppendUseCase(this.pick);
  @override
  Future<void> execute(E event) async {
    final snapshot = bloc.state.log; // read BEFORE await
    await Future<void>.delayed(const Duration(milliseconds: 30));
    emitUpdate(
      newState: bloc.state.copyWith(log: [...snapshot, pick(event)]),
      groupsToRebuild: {'log'},
    );
  }
}

class DropUseCase extends BlocUseCase<RaceBloc, DropEvent> {
  @override
  Future<void> execute(DropEvent event) async {
    emitUpdate(
      newState: bloc.state.copyWith(runs: bloc.state.runs + 1),
      groupsToRebuild: {'runs'},
    );
    await Future<void>.delayed(const Duration(milliseconds: 50)); // stay busy
  }
}

class RaceBloc extends JuiceBloc<RaceState> {
  RaceBloc()
      : super(const RaceState(), [
          () => UseCaseBuilder(
                typeOfEvent: SeqEvent,
                useCaseGenerator: () => _AppendUseCase<SeqEvent>((e) => e.n),
                concurrency: EventConcurrency.sequential,
              ),
          () => UseCaseBuilder(
                typeOfEvent: ConcEvent,
                useCaseGenerator: () => _AppendUseCase<ConcEvent>((e) => e.n),
                concurrency: EventConcurrency.concurrent,
              ),
          () => UseCaseBuilder(
                typeOfEvent: DropEvent,
                useCaseGenerator: () => DropUseCase(),
                concurrency: EventConcurrency.droppable,
              ),
        ]);
}

void main() {
  Future<void> settle([int ms = 160]) =>
      Future<void>.delayed(Duration(milliseconds: ms));

  test('sequential: same-type events queue and preserve order (no clobber)',
      () async {
    final bloc = RaceBloc();
    bloc.send(SeqEvent(1)); // fire-and-forget
    bloc.send(SeqEvent(2));
    bloc.send(SeqEvent(3));
    await settle();

    expect(bloc.state.log, [1, 2, 3]); // all preserved, in order
    await bloc.close();
  });

  test('concurrent: same race clobbers (control — proves the bug is real)',
      () async {
    final bloc = RaceBloc();
    bloc.send(ConcEvent(1));
    bloc.send(ConcEvent(2));
    bloc.send(ConcEvent(3));
    await settle();

    // All three read the empty snapshot before any await completed, so the last
    // write wins → only one survives. (This is exactly what sequential fixes.)
    expect(bloc.state.log.length, 1);
    await bloc.close();
  });

  test('droppable: events arriving while one runs are dropped', () async {
    final bloc = RaceBloc();
    bloc.send(DropEvent());
    bloc.send(DropEvent()); // dropped — first still busy
    bloc.send(DropEvent()); // dropped
    await settle();

    expect(bloc.state.runs, 1);
    await bloc.close();
  });

  test('close mid-flight: queued sequential runs do not emit after close',
      () async {
    final bloc = RaceBloc();
    bloc.send(SeqEvent(1));
    bloc.send(SeqEvent(2));
    bloc.send(SeqEvent(3));
    await Future<void>.delayed(const Duration(milliseconds: 10)); // mid first run
    await bloc.close(); // should not throw

    await Future<void>.delayed(const Duration(milliseconds: 120));
    // Reaching here without an emit-after-close throw is the assertion; the
    // queued runs were skipped by the dispatcher's disposed guard.
    expect(bloc.isClosed, isTrue);
  });

  test('default concurrency is concurrent (unspecified builder unchanged)', () {
    final b = UseCaseBuilder(
      typeOfEvent: SeqEvent,
      useCaseGenerator: () => DropUseCase(),
    );
    expect(b.concurrency, EventConcurrency.concurrent);
  });
}
