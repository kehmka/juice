import 'package:juice/juice.dart';
import '../todo.dart';

class TodoListWidget extends StatelessJuiceWidget<TodoBloc> {
  TodoListWidget({super.key, super.groups = const {"todo_list"}});

  @override
  Widget onBuild(BuildContext context, StreamStatus status) {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: bloc.state.todos.length,
      itemBuilder: (context, index) {
        final todo = bloc.state.todos[index];

        // Generate a unique color based on the todo's content
        final hue = (todo.description.length * 137.5) % 360;
        final color = HSLColor.fromAHSL(
          1.0,
          hue,
          0.7,
          todo.isComplete ? 0.8 : 0.4,
        ).toColor();

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Dismissible(
            key: ValueKey(todo.id),
            background: Container(
              decoration: BoxDecoration(
                color: Colors.red.shade300,
                borderRadius: BorderRadius.circular(12),
              ),
              alignment: Alignment.centerRight,
              padding: const EdgeInsets.only(right: 16),
              child: const Icon(Icons.delete, color: Colors.white),
            ),
            direction: DismissDirection.endToStart,
            onDismissed: (_) => bloc.send(RemoveTodoEvent(id: todo.id)),
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [color.withValues(alpha: 0.7), color],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: color.withValues(alpha: 0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: ListTile(
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                title: Text(
                  todo.description,
                  style: TextStyle(
                    color: Colors.white,
                    decoration:
                        todo.isComplete ? TextDecoration.lineThrough : null,
                    decorationColor: Colors.white.withValues(alpha: 0.5),
                  ),
                ),
                trailing: Transform.scale(
                  scale: 1.2,
                  child: Checkbox(
                    value: todo.isComplete,
                    onChanged: (_) => bloc.send(ToggleTodoEvent(id: todo.id)),
                    checkColor: color,
                    fillColor: WidgetStateProperty.resolveWith(
                      (states) => states.contains(WidgetState.selected)
                          ? Colors.white
                          : Colors.white.withValues(alpha: 0.7),
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
                onLongPress: () => bloc.send(RemoveTodoEvent(id: todo.id)),
              ),
            ),
          ),
        );
      },
    );
  }
}
