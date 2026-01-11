import 'package:juice/juice.dart';

/// Status of a simulated task.
enum TaskStatus {
  pending,
  running,
  completed,
  canceled,
}

/// A simulated async task with progress tracking.
class TaskInfo {
  final String id;
  final String name;
  final double progress; // 0.0 - 1.0
  final TaskStatus status;
  final Duration totalDuration;

  const TaskInfo({
    required this.id,
    required this.name,
    required this.progress,
    required this.status,
    required this.totalDuration,
  });

  TaskInfo copyWith({
    String? id,
    String? name,
    double? progress,
    TaskStatus? status,
    Duration? totalDuration,
  }) {
    return TaskInfo(
      id: id ?? this.id,
      name: name ?? this.name,
      progress: progress ?? this.progress,
      status: status ?? this.status,
      totalDuration: totalDuration ?? this.totalDuration,
    );
  }

  /// Whether this task is still running.
  bool get isActive => status == TaskStatus.pending || status == TaskStatus.running;
}

/// State for the LifecycleBloc demo.
class LifecycleDemoState extends BlocState {
  final List<TaskInfo> tasks;
  final bool scopeActive;
  final bool scopeEnding;
  final bool scopeEnded; // Brief state to show "Ended" phase
  final bool addSlowCleanup;
  final List<String> eventLog;

  const LifecycleDemoState({
    this.tasks = const [],
    this.scopeActive = false,
    this.scopeEnding = false,
    this.scopeEnded = false,
    this.addSlowCleanup = false,
    this.eventLog = const [],
  });

  LifecycleDemoState copyWith({
    List<TaskInfo>? tasks,
    bool? scopeActive,
    bool? scopeEnding,
    bool? scopeEnded,
    bool? addSlowCleanup,
    List<String>? eventLog,
  }) {
    return LifecycleDemoState(
      tasks: tasks ?? this.tasks,
      scopeActive: scopeActive ?? this.scopeActive,
      scopeEnding: scopeEnding ?? this.scopeEnding,
      scopeEnded: scopeEnded ?? this.scopeEnded,
      addSlowCleanup: addSlowCleanup ?? this.addSlowCleanup,
      eventLog: eventLog ?? this.eventLog,
    );
  }

  /// Add a log entry (newest first).
  LifecycleDemoState withLog(String message) {
    final timestamp = DateTime.now().toString().substring(11, 19);
    return copyWith(
      eventLog: ['[$timestamp] $message', ...eventLog],
    );
  }

  /// Count of active (pending/running) tasks.
  int get activeTaskCount => tasks.where((t) => t.isActive).length;
}

/// Rebuild groups for the demo.
abstract class LifecycleDemoGroups {
  static const tasks = 'lifecycle_demo_tasks';
  static const controls = 'lifecycle_demo_controls';
  static const log = 'lifecycle_demo_log';
  static const all = {tasks, controls, log};
}
