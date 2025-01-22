import 'package:flutter_test/flutter_test.dart';
import '../lib/blocs/blocs.dart';

void main() {
  group('TodoBloc Tests', () {
    late TodoBloc bloc;

    setUp(() {
      // Initialize the TodoBloc before each test
      bloc = TodoBloc();
    });

    tearDown(() {
      // Close the bloc after each test
      bloc.close();
    });

    test('Initial state has an empty todo list', () {
      expect(bloc.state.todos, []);
    });

    test('AddTodoEvent adds a new todo', () async {
      // Dispatch AddTodoEvent
      await bloc.send(AddTodoEvent(description: 'Test Task 1'));

      // Verify the updated state
      expect(bloc.state.todos.length, 1);
      expect(bloc.state.todos.first.description, 'Test Task 1');
      expect(bloc.state.todos.first.isComplete, false);
    });

    test('RemoveTodoEvent removes a todo', () async {
      // Add a todo first
      await bloc.send(AddTodoEvent(description: 'Test Task 1'));

      // Dispatch RemoveTodoEvent
      final todoId = bloc.state.todos.first.id;
      await bloc.send(RemoveTodoEvent(id: todoId));

      // Verify the updated state
      expect(bloc.state.todos, []);
    });

    test('ToggleTodoEvent toggles the completion status of a todo', () async {
      // Add a todo first
      await bloc.send(AddTodoEvent(description: 'Test Task 1'));

      // Dispatch ToggleTodoEvent
      final todoId = bloc.state.todos.first.id;
      await bloc.send(ToggleTodoEvent(id: todoId));

      // Verify the updated state
      expect(bloc.state.todos.first.isComplete, true);

      // Toggle back
      await bloc.send(ToggleTodoEvent(id: todoId));

      // Verify the updated state again
      expect(bloc.state.todos.first.isComplete, false);
    });
  });
}
