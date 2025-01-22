import 'package:juice/juice.dart';
import 'todo.dart';

import 'use_cases/add_todo_use_case.dart';
import 'use_cases/update_todo_use_case.dart';
import 'use_cases/remove_todo_use_case.dart';
import 'use_cases/toggle_todo_use_case.dart';

class TodoBloc extends JuiceBloc<TodoState> {
  TodoBloc()
      : super(
          TodoState(todos: []),
          [
            () => UseCaseBuilder(
                typeOfEvent: AddTodoEvent,
                useCaseGenerator: () => AddTodoUseCase()),
            () => UseCaseBuilder(
                typeOfEvent: UpdateTodoEvent,
                useCaseGenerator: () => UpdateTodoUseCase()),
            () => UseCaseBuilder(
                typeOfEvent: RemoveTodoEvent,
                useCaseGenerator: () => RemoveTodoUseCase()),
            () => UseCaseBuilder(
                typeOfEvent: ToggleTodoEvent,
                useCaseGenerator: () => ToggleTodoUseCase()),
          ],
          [],
        );
}
