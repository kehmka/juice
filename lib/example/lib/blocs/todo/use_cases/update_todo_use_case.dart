import 'package:juice/juice.dart';
import '../todo.dart';

class UpdateTodoUseCase extends BlocUseCase<TodoBloc, UpdateTodoEvent> {
  @override
  Future<void> execute(UpdateTodoEvent event) async {
    final updatedTodos = bloc.state.todos.map((todo) {
      if (todo.id == event.id) {
        return todo.copyWith(description: event.newDescription);
      }
      return todo;
    }).toList();

    emitUpdate(
      groupsToRebuild: {"todo_list"},
      newState: bloc.state.copyWith(todos: updatedTodos),
    );
  }
}
