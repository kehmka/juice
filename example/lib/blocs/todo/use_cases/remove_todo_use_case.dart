import 'package:juice/juice.dart';
import '../todo.dart';

class RemoveTodoUseCase extends BlocUseCase<TodoBloc, RemoveTodoEvent> {
  @override
  Future<void> execute(RemoveTodoEvent event) async {
    final filteredTodos =
        bloc.state.todos.where((todo) => todo.id != event.id).toList();

    emitUpdate(
      groupsToRebuild: {"todo_list"},
      newState: bloc.state.copyWith(todos: filteredTodos),
    );
  }
}
