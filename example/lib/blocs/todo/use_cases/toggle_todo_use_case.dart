import 'package:juice/juice.dart';
import '../todo.dart';

class ToggleTodoUseCase extends BlocUseCase<TodoBloc, ToggleTodoEvent> {
  @override
  Future<void> execute(ToggleTodoEvent event) async {
    final toggledTodos = bloc.state.todos.map((todo) {
      if (todo.id == event.id) {
        return todo.copyWith(isComplete: !todo.isComplete);
      }
      return todo;
    }).toList();

    emitUpdate(
      groupsToRebuild: {"todo_list"},
      newState: bloc.state.copyWith(todos: toggledTodos),
    );
  }
}
