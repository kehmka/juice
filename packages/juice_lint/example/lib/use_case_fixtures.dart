// Fixtures for juice_lint's bloc and use-case rules:
// juice_missing_concurrency_mode and juice_stale_read_across_await.
// Same `// expect_lint:` convention as fixtures.dart.
import 'package:juice/juice.dart';

class ItemsState extends BlocState {
  final List<String> items;
  final int count;
  final String? selectedId;
  const ItemsState({this.items = const [], this.count = 0, this.selectedId});

  ItemsState copyWith({List<String>? items, int? count}) => ItemsState(
    items: items ?? this.items,
    count: count ?? this.count,
    selectedId: selectedId,
  );
}

abstract final class ItemsGroups {
  static const list = 'items:list';
}

class AddItemEvent extends EventBase {
  final String name;
  AddItemEvent(this.name);
}

class RenameItemEvent extends EventBase {}

class RefreshEvent extends EventBase {}

class SelectEvent extends EventBase {}

class SaveEvent extends EventBase {}

class CountEvent extends EventBase {}

class RollbackEvent extends EventBase {}

Future<String> createRemote(String name) async => name;

class ItemsBloc extends JuiceBloc<ItemsState> {
  ItemsBloc()
    : super(const ItemsState(), [
        // --- juice_missing_concurrency_mode ---------------------------------
        // expect_lint: juice_missing_concurrency_mode
        () => UseCaseBuilder(
          typeOfEvent: AddItemEvent,
          useCaseGenerator: () => AddItemUseCase(),
        ),
        // expect_lint: juice_missing_concurrency_mode
        () => UseCaseBuilder.typed(() => RenameItemUseCase()),
        // Declared modes → fine.
        () => UseCaseBuilder(
          typeOfEvent: RefreshEvent,
          useCaseGenerator: () => RefreshUseCase(),
          concurrency: EventConcurrency.droppable,
        ),
        () => UseCaseBuilder.typed(
          () => SelectUseCase(),
          concurrency: EventConcurrency.concurrent,
        ),
        () => UseCaseBuilder.typed(
          () => SaveUseCase(),
          concurrency: EventConcurrency.sequential,
        ),
        () => UseCaseBuilder.typed(
          () => CountUseCase(),
          concurrency: EventConcurrency.sequential,
        ),
        () => UseCaseBuilder.typed(
          () => RollbackUseCase(),
          concurrency: EventConcurrency.sequential,
        ),
      ]);
}

// --- juice_stale_read_across_await -------------------------------------------

/// The bug: snapshot → await → rebuild from the snapshot.
class AddItemUseCase extends BlocUseCase<ItemsBloc, AddItemEvent> {
  @override
  Future<void> execute(AddItemEvent event) async {
    final items = bloc.state.items; // snapshot
    final created = await createRemote(event.name); // another event may emit
    emitUpdate(
      // expect_lint: juice_stale_read_across_await
      newState: bloc.state.copyWith(items: [...items, created]),
      groupsToRebuild: {ItemsGroups.list},
    );
  }
}

/// The whole-state snapshot is the same bug.
class RenameItemUseCase extends BlocUseCase<ItemsBloc, RenameItemEvent> {
  @override
  Future<void> execute(RenameItemEvent event) async {
    final state = bloc.state;
    await createRemote('x');
    emitUpdate(
      // expect_lint: juice_stale_read_across_await
      newState: state.copyWith(count: 1),
      groupsToRebuild: {ItemsGroups.list},
    );
  }
}

/// The fix: read bloc.state AFTER the await → fine.
class RefreshUseCase extends BlocUseCase<ItemsBloc, RefreshEvent> {
  @override
  Future<void> execute(RefreshEvent event) async {
    final created = await createRemote('y');
    final items = bloc.state.items; // read after the await
    emitUpdate(
      newState: bloc.state.copyWith(items: [...items, created]),
      groupsToRebuild: {ItemsGroups.list},
    );
  }
}

/// A snapshot used BEFORE the await (optimistic emit) → fine.
class SelectUseCase extends BlocUseCase<ItemsBloc, SelectEvent> {
  @override
  Future<void> execute(SelectEvent event) async {
    final items = bloc.state.items;
    emitWaiting(
      newState: bloc.state.copyWith(items: [...items, 'pending']),
      groupsToRebuild: {ItemsGroups.list},
    );
    await createRemote('z');
    emitUpdate(
      newState: bloc.state.copyWith(count: bloc.state.count + 1),
      groupsToRebuild: {ItemsGroups.list},
    );
  }
}

/// A scalar read before the await (an id used as a request key) is out of
/// scope; a snapshot used only OUTSIDE newState (groups, logging) → fine.
class SaveUseCase extends BlocUseCase<ItemsBloc, SaveEvent> {
  @override
  Future<void> execute(SaveEvent event) async {
    final id = bloc.state.selectedId;
    final before = bloc.state.items;
    await createRemote(id ?? '');
    emitUpdate(
      newState: bloc.state.copyWith(count: id == null ? 0 : 1),
      groupsToRebuild: {ItemsGroups.list, 'items:${before.length}'},
    );
  }
}

/// A snapshot refreshed after the await (reassigned) → fine.
class CountUseCase extends BlocUseCase<ItemsBloc, CountEvent> {
  @override
  Future<void> execute(CountEvent event) async {
    var items = bloc.state.items;
    await createRemote('w');
    items = bloc.state.items;
    emitUpdate(
      newState: bloc.state.copyWith(items: [...items, 'n']),
      groupsToRebuild: {ItemsGroups.list},
    );
  }
}

/// A deliberate rollback on a sequential event, silenced at the use with the
/// documented escape.
class RollbackUseCase extends BlocUseCase<ItemsBloc, RollbackEvent> {
  @override
  Future<void> execute(RollbackEvent event) async {
    final previous = bloc.state;
    try {
      await createRemote('v');
    } catch (e) {
      emitFailure(
        // ignore: juice_lint/juice_stale_read_across_await
        newState: previous,
        groupsToRebuild: {ItemsGroups.list},
        error: e,
      );
    }
  }
}
