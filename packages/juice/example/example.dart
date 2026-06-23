// ignore_for_file: avoid_print, must_be_immutable
import 'package:juice/juice.dart';

// --- State ---
class CounterState extends BlocState {
  final int count;

  const CounterState({this.count = 0});

  CounterState copyWith({int? count}) =>
      CounterState(count: count ?? this.count);
}

// --- Events ---
class IncrementEvent extends EventBase {}

class DecrementEvent extends EventBase {}

// --- Use Cases ---
class IncrementUseCase extends BlocUseCase<CounterBloc, IncrementEvent> {
  @override
  Future<void> execute(IncrementEvent event) async {
    emitUpdate(
      newState: bloc.state.copyWith(count: bloc.state.count + 1),
      groupsToRebuild: {'counter'},
    );
  }
}

class DecrementUseCase extends BlocUseCase<CounterBloc, DecrementEvent> {
  @override
  Future<void> execute(DecrementEvent event) async {
    emitUpdate(
      newState: bloc.state.copyWith(count: bloc.state.count - 1),
      groupsToRebuild: {'counter'},
    );
  }
}

// --- BLoC ---
class CounterBloc extends JuiceBloc<CounterState> {
  CounterBloc()
      : super(
          const CounterState(),
          [
            () => UseCaseBuilder(
                  typeOfEvent: IncrementEvent,
                  useCaseGenerator: () => IncrementUseCase(),
                ),
            () => UseCaseBuilder(
                  typeOfEvent: DecrementEvent,
                  useCaseGenerator: () => DecrementUseCase(),
                ),
          ],
        );
}

// --- Widget ---
class CounterWidget extends StatelessJuiceWidget<CounterBloc> {
  CounterWidget({super.key, super.groups = const {'counter'}});

  @override
  Widget onBuild(BuildContext context, StreamStatus status) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text('Count: ${bloc.state.count}',
            style: const TextStyle(fontSize: 24)),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ElevatedButton(
              onPressed: () => bloc.send(DecrementEvent()),
              child: const Text('-'),
            ),
            const SizedBox(width: 16),
            ElevatedButton(
              onPressed: () => bloc.send(IncrementEvent()),
              child: const Text('+'),
            ),
          ],
        ),
      ],
    );
  }
}

// --- App ---
void main() {
  // Register bloc with BlocScope
  BlocScope.register<CounterBloc>(
    () => CounterBloc(),
    lifecycle: BlocLifecycle.permanent,
  );

  runApp(
    MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: const Text('Juice Counter')),
        body: Center(child: CounterWidget()),
      ),
    ),
  );
}

// === EntityStatus: per-item async state (1.6.0) =============================
// A list whose rows each have their OWN async lifecycle. `EntityStatuses<K>`
// lives in the state; `BlocUseCase.guardEntity` brackets the per-row work
// (waiting → idle, or failure on throw, with cleanup guaranteed). So one row
// can be in flight or failed while the rest stay interactive — no bloc-wide
// spinner. See doc/ENTITY_STATUS_GUIDE.md for the full walkthrough.

class RowsState extends BlocState {
  final List<String> ids;
  // Absent keys read as idle, so this only ever holds in-flight / failed rows.
  final EntityStatuses<String> rowStatus;

  const RowsState({
    this.ids = const [],
    this.rowStatus = const EntityStatuses<String>(),
  });

  RowsState copyWith({List<String>? ids, EntityStatuses<String>? rowStatus}) =>
      RowsState(ids: ids ?? this.ids, rowStatus: rowStatus ?? this.rowStatus);
}

class RefreshRowEvent extends EventBase {
  RefreshRowEvent(this.id);
  final String id;
}

class RefreshRowUseCase extends BlocUseCase<RowsBloc, RefreshRowEvent> {
  @override
  Future<void> execute(RefreshRowEvent event) => guardEntity<String, void>(
        event.id,
        // Where the status map lives, and how to write an updated one back.
        read: (bloc) => bloc.state.rowStatus,
        write: (statuses) => bloc.state.copyWith(rowStatus: statuses),
        groupsToRebuild: {'rows'},
        // The risky per-row work; may take a while and may throw. guardEntity
        // marks this row waiting around it, then idle on success / failure on
        // throw — you never touch the status map by hand.
        action: () async {
          await Future<void>.delayed(const Duration(milliseconds: 300));
        },
      );
}

class RowsBloc extends JuiceBloc<RowsState> {
  RowsBloc()
      : super(
          const RowsState(ids: ['a', 'b', 'c']),
          [
            () => UseCaseBuilder(
                  typeOfEvent: RefreshRowEvent,
                  useCaseGenerator: () => RefreshRowUseCase(),
                ),
          ],
        );
}

class RowsWidget extends StatelessJuiceWidget<RowsBloc> {
  RowsWidget({super.key, super.groups = const {'rows'}});

  @override
  Widget onBuild(BuildContext context, StreamStatus status) {
    return Column(
      children: [
        for (final id in bloc.state.ids)
          ListTile(
            title: Text('Row $id'),
            // Each row reads its OWN status, independent of the others.
            trailing: bloc.state.rowStatus.statusOf(id).when(
                  idle: () => IconButton(
                    icon: const Icon(Icons.refresh),
                    onPressed: () => bloc.send(RefreshRowEvent(id)),
                  ),
                  waiting: () => const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  failure: (error) => IconButton(
                    icon: const Icon(Icons.error_outline),
                    tooltip: '$error — tap to retry',
                    onPressed: () => bloc.send(RefreshRowEvent(id)),
                  ),
                ),
          ),
      ],
    );
  }
}
