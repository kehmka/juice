import 'package:juice/juice.dart';
import 'package:juice_network/juice_network.dart';

// =============================================================================
// State
// =============================================================================

class CoalesceState extends BlocState {
  final int tapCount;
  final int networkCalls;
  final int coalescedCount;
  final List<String> logs;

  const CoalesceState({
    this.tapCount = 0,
    this.networkCalls = 0,
    this.coalescedCount = 0,
    this.logs = const [],
  });

  CoalesceState copyWith({
    int? tapCount,
    int? networkCalls,
    int? coalescedCount,
    List<String>? logs,
  }) {
    return CoalesceState(
      tapCount: tapCount ?? this.tapCount,
      networkCalls: networkCalls ?? this.networkCalls,
      coalescedCount: coalescedCount ?? this.coalescedCount,
      logs: logs ?? this.logs,
    );
  }
}

// =============================================================================
// Events
// =============================================================================

class FireRequestEvent extends EventBase {}

class FireBurstEvent extends EventBase {
  final int count;
  FireBurstEvent({this.count = 10});
}

class ResetCoalesceEvent extends EventBase {}

// =============================================================================
// Use Cases
// =============================================================================

class FireRequestUseCase extends BlocUseCase<CoalesceBloc, FireRequestEvent> {
  @override
  Future<void> execute(FireRequestEvent event) async {
    final newTapCount = bloc.state.tapCount + 1;
    _addLog('Tap #$newTapCount - firing request');
    emitUpdate(newState: bloc.state.copyWith(tapCount: newTapCount));

    final coalescedBefore = bloc.fetchBloc.state.stats.coalescedCount;

    await bloc.fetchBloc.send(GetEvent(
      url: '/posts/1',
      cachePolicy: CachePolicy.networkOnly,
      decode: (raw) => raw,
    ));

    final stats = bloc.fetchBloc.state.stats;
    if (stats.coalescedCount > coalescedBefore) {
      _addLog('Request was COALESCED (shared existing call)');
      emitUpdate(newState: bloc.state.copyWith(coalescedCount: stats.coalescedCount));
    } else {
      _addLog('Network call completed');
      emitUpdate(newState: bloc.state.copyWith(networkCalls: bloc.state.networkCalls + 1));
    }
  }

  void _addLog(String message) {
    final timestamp = DateTime.now().toIso8601String().substring(11, 23);
    final newLogs = ['$timestamp $message', ...bloc.state.logs];
    if (newLogs.length > 50) newLogs.removeLast();
    emitUpdate(newState: bloc.state.copyWith(logs: newLogs));
  }
}

class FireBurstUseCase extends BlocUseCase<CoalesceBloc, FireBurstEvent> {
  @override
  Future<void> execute(FireBurstEvent event) async {
    _addLog('Firing BURST of ${event.count} simultaneous requests...');

    final coalescedBefore = bloc.fetchBloc.state.stats.coalescedCount;
    final successBefore = bloc.fetchBloc.state.stats.successCount;

    // Update tap count for all requests
    emitUpdate(newState: bloc.state.copyWith(tapCount: bloc.state.tapCount + event.count));

    // Fire all requests simultaneously
    final futures = <Future>[];
    for (var i = 0; i < event.count; i++) {
      futures.add(bloc.fetchBloc.send(GetEvent(
        url: '/posts/1',
        cachePolicy: CachePolicy.networkOnly,
        decode: (raw) => raw,
      )));
    }

    await Future.wait(futures);

    final stats = bloc.fetchBloc.state.stats;
    final newCoalesced = stats.coalescedCount - coalescedBefore;
    final newSuccess = stats.successCount - successBefore;

    _addLog('Burst complete: $newSuccess network calls, $newCoalesced coalesced');
    emitUpdate(newState: bloc.state.copyWith(
      coalescedCount: stats.coalescedCount,
      networkCalls: bloc.state.networkCalls + newSuccess,
    ));
  }

  void _addLog(String message) {
    final timestamp = DateTime.now().toIso8601String().substring(11, 23);
    final newLogs = ['$timestamp $message', ...bloc.state.logs];
    if (newLogs.length > 50) newLogs.removeLast();
    emitUpdate(newState: bloc.state.copyWith(logs: newLogs));
  }
}

class ResetCoalesceUseCase extends BlocUseCase<CoalesceBloc, ResetCoalesceEvent> {
  @override
  Future<void> execute(ResetCoalesceEvent event) async {
    bloc.fetchBloc.send(ResetStatsEvent());
    final timestamp = DateTime.now().toIso8601String().substring(11, 23);
    emitUpdate(newState: const CoalesceState().copyWith(
      logs: ['$timestamp Stats reset'],
    ));
  }
}

// =============================================================================
// Bloc
// =============================================================================

class CoalesceBloc extends JuiceBloc<CoalesceState> {
  final FetchBloc fetchBloc;

  CoalesceBloc({required this.fetchBloc})
      : super(
          const CoalesceState(),
          [
            () => UseCaseBuilder(
                  typeOfEvent: FireRequestEvent,
                  useCaseGenerator: () => FireRequestUseCase(),
                ),
            () => UseCaseBuilder(
                  typeOfEvent: FireBurstEvent,
                  useCaseGenerator: () => FireBurstUseCase(),
                ),
            () => UseCaseBuilder(
                  typeOfEvent: ResetCoalesceEvent,
                  useCaseGenerator: () => ResetCoalesceUseCase(),
                ),
          ],
        );
}
