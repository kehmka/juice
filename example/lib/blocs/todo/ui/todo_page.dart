import 'package:flutter/material.dart';
import 'package:juice/juice.dart';
import 'todo_list_widget.dart';
import 'todo_input_widget.dart';

class TodoPage extends StatelessWidget {
  const TodoPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Todo Example')),
      body: Column(
        children: [
          Expanded(child: TodoListWidget()),
          TodoInputWidget(),
        ],
      ),
    );
  }
}
