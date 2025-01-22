import 'package:juice/juice.dart';

abstract class TodoEvent extends EventBase {}

class AddTodoEvent extends TodoEvent {
  final String description;

  AddTodoEvent({required this.description});
}

class UpdateTodoEvent extends TodoEvent {
  final String id;
  final String newDescription;

  UpdateTodoEvent({required this.id, required this.newDescription});
}

class RemoveTodoEvent extends TodoEvent {
  final String id;

  RemoveTodoEvent({required this.id});
}

class ToggleTodoEvent extends TodoEvent {
  final String id;

  ToggleTodoEvent({required this.id});
}
