import 'package:juice/juice.dart';
import '../todo.dart';

class AddTodoUseCase extends BlocUseCase<TodoBloc, AddTodoEvent> {
  @override
  Future<void> execute(AddTodoEvent event) async {
    final newTodo = Todo(
      id: DateTime.now().toIso8601String(),
      description: event.description,
      isComplete: false,
    );

    emitUpdate(
      groupsToRebuild: {"todo_list"},
      newState: bloc.state.copyWith(todos: [...bloc.state.todos, newTodo]),
    );
  }
}
