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
                useCaseGenerator: () => AddTodoUseCase(),
                concurrency: EventConcurrency.sequential),
            () => UseCaseBuilder(
                typeOfEvent: UpdateTodoEvent,
                useCaseGenerator: () => UpdateTodoUseCase(),
                concurrency: EventConcurrency.sequential),
            () => UseCaseBuilder(
                typeOfEvent: RemoveTodoEvent,
                useCaseGenerator: () => RemoveTodoUseCase(),
                concurrency: EventConcurrency.sequential),
            () => UseCaseBuilder(
                typeOfEvent: ToggleTodoEvent,
                useCaseGenerator: () => ToggleTodoUseCase(),
                concurrency: EventConcurrency.sequential),
          ],
          [],
        );
}
