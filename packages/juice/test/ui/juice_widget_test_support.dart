import 'package:flutter_test/flutter_test.dart';
import 'package:juice/juice.dart';

/// Shared fixtures for the StatelessJuiceWidget / JuiceWidgetState widget
/// tests: three distinct bloc types over one tiny state, and a single event
/// whose use case emits the requested [StreamStatus] kind on the requested
/// rebuild groups.

class WState extends BlocState {
  final int v;
  const WState([this.v = 0]);
}

enum WKind { update, waiting, failure, cancel }

class WEmit extends EventBase {
  final int v;
  final WKind kind;
  WEmit(this.v, {this.kind = WKind.update, Set<String> groups = const {'a'}}) {
    groupsToRebuild = groups;
  }
}

class WEmitUseCase extends BlocUseCase<JuiceBloc<WState>, WEmit> {
  @override
  Future<void> execute(WEmit event) async {
    final s = WState(event.v);
    final g = event.groupsToRebuild;
    switch (event.kind) {
      case WKind.update:
        emitUpdate(newState: s, groupsToRebuild: g);
      case WKind.waiting:
        emitWaiting(newState: s, groupsToRebuild: g);
      case WKind.failure:
        emitFailure(newState: s, groupsToRebuild: g, error: 'boom');
      case WKind.cancel:
        emitCancel(newState: s, groupsToRebuild: g);
    }
  }
}

abstract class WBase extends JuiceBloc<WState> {
  WBase([int initial = 0])
      : super(WState(initial), [
          () => UseCaseBuilder(
                typeOfEvent: WEmit,
                useCaseGenerator: () => WEmitUseCase(),
                concurrency: EventConcurrency.sequential,
              ),
        ]);
}

class BlocA extends WBase {
  BlocA([super.initial]);
}

class BlocB extends WBase {
  BlocB([super.initial]);
}

class BlocC extends WBase {
  BlocC([super.initial]);
}

/// Legacy resolver that hands out fixed instances (no lease management).
class MapResolver extends BlocDependencyResolver {
  MapResolver(this.blocs);
  final Map<Type, JuiceBloc<BlocState>> blocs;
  int resolveCount = 0;

  @override
  T resolve<T extends JuiceBloc<BlocState>>({Map<String, dynamic>? args}) {
    resolveCount++;
    return blocs[T]! as T;
  }
}

/// Discards framework logs so widget-test output stays readable.
class SilentLogger implements JuiceLogger {
  @override
  void log(String message,
      {Level level = Level.info, Map<String, dynamic>? context}) {}

  @override
  void logError(String message, Object error, StackTrace stackTrace,
      {Map<String, dynamic>? context}) {}
}

/// Standard per-test setup: quiet logger + clean BlocScope.
Future<void> quietReset() async {
  JuiceLoggerConfig.configureLogger(SilentLogger());
  await BlocScope.reset();
}

/// Standard per-test teardown.
Future<void> restoreReset() async {
  await BlocScope.reset();
  JuiceLoggerConfig.configureLogger(DefaultJuiceLogger());
}

/// Short label for a status, used by widgets under test.
String kindOf(StreamStatus s) => s.when(
      updating: (_, __, ___) => 'U',
      waiting: (_, __, ___) => 'W',
      failure: (_, __, ___) => 'F',
      canceling: (_, __, ___) => 'C',
    );

/// Sends [e] to [bloc] outside the fake-async zone and pumps the result.
Future<void> fire(WidgetTester tester, JuiceBloc bloc, EventBase e) async {
  await tester.runAsync(() => bloc.send(e));
  await tester.pump();
}

/// Closes [bloc] for real and pumps the resulting frame.
Future<void> closeBloc(WidgetTester tester, JuiceBloc bloc) async {
  await tester.runAsync(() => bloc.close());
  await tester.pump();
  // Merged (rxdart) streams forward done across both zones; give them a
  // second real-async turn plus a frame.
  await tester.runAsync(() => Future<void>.delayed(Duration.zero));
  await tester.pump();
}

/// Removes the tree (unmounting every widget) and lets async closes finish.
Future<void> unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.runAsync(() => Future<void>.delayed(Duration.zero));
}
