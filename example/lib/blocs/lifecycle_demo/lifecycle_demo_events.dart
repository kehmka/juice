import 'package:juice/juice.dart';

/// Start the demo - creates a scope and spawns tasks.
class StartDemoEvent extends EventBase {}

/// End the demo - triggers cleanup sequence.
class EndDemoEvent extends EventBase {}

/// Toggle whether to add a slow cleanup task.
class ToggleSlowCleanupEvent extends EventBase {}

/// Internal: Update a task's progress.
class UpdateTaskProgressEvent extends EventBase {
  final String taskId;
  final double progress;

  UpdateTaskProgressEvent({
    required this.taskId,
    required this.progress,
  });
}

/// Internal: Mark a task as completed.
class TaskCompletedEvent extends EventBase {
  final String taskId;

  TaskCompletedEvent({required this.taskId});
}

/// Internal: Cancel all running tasks.
class CancelAllTasksEvent extends EventBase {}

/// Internal: Add a log entry.
class AddLogEvent extends EventBase {
  final String message;

  AddLogEvent({required this.message});
}

/// Internal: Mark scope as ending.
class ScopeEndingEvent extends EventBase {}

/// Internal: Mark scope as ended.
class ScopeEndedEvent extends EventBase {}

/// Internal: Reset demo to idle state after showing "ended" briefly.
class ResetDemoEvent extends EventBase {}

/// Internal: Update demo state directly.
class UpdateDemoStateEvent extends EventBase {
  final List<dynamic>? tasks;
  final bool? scopeActive;
  final bool? scopeEnding;

  UpdateDemoStateEvent({
    this.tasks,
    this.scopeActive,
    this.scopeEnding,
  });
}
