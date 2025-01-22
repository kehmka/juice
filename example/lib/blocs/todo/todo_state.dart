import 'package:juice/juice.dart';

class TodoState extends BlocState {
  final List<Todo> todos;

  TodoState({required this.todos});

  TodoState copyWith({List<Todo>? todos}) {
    return TodoState(todos: todos ?? this.todos);
  }
}

class Todo {
  final String id;
  final String description;
  final bool isComplete;

  Todo({
    required this.id,
    required this.description,
    required this.isComplete,
  });

  Todo copyWith({String? description, bool? isComplete}) {
    return Todo(
      id: id,
      description: description ?? this.description,
      isComplete: isComplete ?? this.isComplete,
    );
  }
}
