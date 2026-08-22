import 'package:juice/juice.dart';

/// A Juice-pure consumer of the DevTools mirror: the same `juice:<type>`
/// events `DevtoolsJuiceLogger` posts to the VM, shown in-app as a rolling
/// feed — so the demo PROVES the mirror works without DevTools open.
///
/// THE TRAP THIS FILE TEACHES: a telemetry consumer that is itself a bloc
/// produces telemetry. Every `AppendTelemetryEvent` runs a use case, which
/// logs `use_case_execution`, which the mirror posts, which (unfiltered)
/// would append again — forever. [isSelfTelemetry] is the guard: drop
/// anything this bloc or its use case produced, by name.
abstract final class TelemetryFeedGroups {
  static const feed = 'telemetry:feed';
  static const all = {feed};
}

class TelemetryFeedState extends BlocState {
  const TelemetryFeedState({this.lines = const []});

  /// Newest LAST, capped at [max] — the panel reads top-to-bottom in time.
  final List<String> lines;
  static const int max = 12;

  TelemetryFeedState copyWith({List<String>? lines}) =>
      TelemetryFeedState(lines: lines ?? this.lines);
}

abstract class TelemetryFeedEvent extends EventBase {
  @override
  String toString() => runtimeType.toString();
}

class AppendTelemetryEvent extends TelemetryFeedEvent {
  AppendTelemetryEvent(this.line);
  final String line;
}

class AppendTelemetryUseCase
    extends BlocUseCase<TelemetryFeedBloc, AppendTelemetryEvent> {
  @override
  Future<void> execute(AppendTelemetryEvent event) async {
    final next = [...bloc.state.lines, event.line];
    if (next.length > TelemetryFeedState.max) next.removeAt(0);
    emitUpdate(
      newState: bloc.state.copyWith(lines: next),
      groupsToRebuild: {TelemetryFeedGroups.feed},
    );
  }
}

class TelemetryFeedBloc extends JuiceBloc<TelemetryFeedState> {
  TelemetryFeedBloc()
      : super(const TelemetryFeedState(), [
          () => UseCaseBuilder(
                typeOfEvent: AppendTelemetryEvent,
                useCaseGenerator: () => AppendTelemetryUseCase(),
                // Appends mutate the shared list: never interleave.
                concurrency: EventConcurrency.sequential,
              ),
        ], []);

  void append(String line) => send(AppendTelemetryEvent(line));
}

/// True for telemetry produced by the feed itself — the loop guard.
/// Matches by the names the framework puts in the payload (`bloc` on
/// emissions/lifecycle, `useCase` on executions/completions/errors).
bool isSelfTelemetry(Map<String, Object?> data) =>
    data['bloc'] == 'TelemetryFeedBloc' ||
    data['useCase'] == 'AppendTelemetryUseCase';

/// One line per event for the panel: the kind, the actor, and — on the
/// span-closing entries — the elapsed time. Pure, so it's testable.
String telemetryLine(String kind, Map<String, Object?> data) {
  final who = data['useCase'] ?? data['bloc'] ?? '';
  final id = data['executionId'];
  final micros = data['elapsedMicros'];
  final b = StringBuffer(kind.replaceFirst('juice:', ''));
  if ('$who'.isNotEmpty) b.write('  $who');
  if (id != null) b.write('  #$id');
  if (micros is int) b.write('  ${(micros / 1000).toStringAsFixed(1)} ms');
  return b.toString();
}
