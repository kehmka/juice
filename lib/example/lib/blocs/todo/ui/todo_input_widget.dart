import 'package:juice/juice.dart';
import '../todo.dart';

class TodoInputWidget extends StatelessJuiceWidget<TodoBloc> {
  final TextEditingController _controller = TextEditingController();

  TodoInputWidget({super.key, super.groups = optOutOfRebuilds});

  @override
  Widget onBuild(BuildContext context, StreamStatus status) {
    void handleSubmit(String value) {
      if (value.isNotEmpty) {
        bloc.send(AddTodoEvent(description: value));
        _controller.clear();
      }
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            offset: const Offset(0, -2),
            blurRadius: 8,
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: Theme.of(context)
                    .colorScheme
                    .surfaceContainerHighest
                    .withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: Theme.of(context)
                      .colorScheme
                      .outline
                      .withValues(alpha: 0.1),
                ),
              ),
              child: TextField(
                controller: _controller,
                decoration: InputDecoration(
                  hintText: 'Add a new task...',
                  hintStyle: TextStyle(
                    color: Theme.of(context)
                        .colorScheme
                        .onSurfaceVariant
                        .withValues(alpha: 0.7),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 16,
                  ),
                  border: InputBorder.none,
                  prefixIcon: Icon(
                    Icons.task_alt,
                    color: Theme.of(context)
                        .colorScheme
                        .primary
                        .withValues(alpha: 0.5),
                  ),
                ),
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface,
                ),
                onSubmitted: handleSubmit,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Container(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => handleSubmit(_controller.text),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  child: Icon(
                    Icons.add,
                    color: Theme.of(context).colorScheme.onPrimary,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
