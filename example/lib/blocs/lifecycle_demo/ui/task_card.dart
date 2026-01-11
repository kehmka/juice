import 'package:flutter/material.dart';
import '../lifecycle_demo_state.dart';

/// A card displaying a simulated task with progress.
class TaskCard extends StatelessWidget {
  final TaskInfo task;

  const TaskCard({super.key, required this.task});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _StatusIcon(status: task.status),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    task.name,
                    style: const TextStyle(
                      fontWeight: FontWeight.w500,
                      fontSize: 14,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            _ProgressBar(
              progress: task.progress,
              status: task.status,
            ),
            const SizedBox(height: 4),
            Text(
              _statusText(task.status, task.progress),
              style: TextStyle(
                fontSize: 12,
                color: _statusColor(task.status).withValues(alpha: 0.8),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _statusText(TaskStatus status, double progress) {
    switch (status) {
      case TaskStatus.pending:
        return 'Pending...';
      case TaskStatus.running:
        return '${(progress * 100).toInt()}%';
      case TaskStatus.completed:
        return 'Completed';
      case TaskStatus.canceled:
        return 'Canceled';
    }
  }

  Color _statusColor(TaskStatus status) {
    switch (status) {
      case TaskStatus.pending:
        return Colors.blue;
      case TaskStatus.running:
        return Colors.green;
      case TaskStatus.completed:
        return Colors.green;
      case TaskStatus.canceled:
        return Colors.red;
    }
  }
}

class _StatusIcon extends StatelessWidget {
  final TaskStatus status;

  const _StatusIcon({required this.status});

  @override
  Widget build(BuildContext context) {
    IconData icon;
    Color color;

    switch (status) {
      case TaskStatus.pending:
        icon = Icons.hourglass_empty;
        color = Colors.blue;
        break;
      case TaskStatus.running:
        icon = Icons.play_circle_fill;
        color = Colors.green;
        break;
      case TaskStatus.completed:
        icon = Icons.check_circle;
        color = Colors.green;
        break;
      case TaskStatus.canceled:
        icon = Icons.cancel;
        color = Colors.red;
        break;
    }

    return Icon(icon, size: 20, color: color);
  }
}

class _ProgressBar extends StatelessWidget {
  final double progress;
  final TaskStatus status;

  const _ProgressBar({
    required this.progress,
    required this.status,
  });

  @override
  Widget build(BuildContext context) {
    Color color;
    switch (status) {
      case TaskStatus.pending:
        color = Colors.blue;
        break;
      case TaskStatus.running:
        color = Colors.green;
        break;
      case TaskStatus.completed:
        color = Colors.green;
        break;
      case TaskStatus.canceled:
        color = Colors.red;
        break;
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: LinearProgressIndicator(
        value: progress,
        backgroundColor: Colors.grey.shade200,
        valueColor: AlwaysStoppedAnimation<Color>(color),
        minHeight: 8,
      ),
    );
  }
}
