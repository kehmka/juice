import 'dart:math';
import 'package:juice/juice.dart';
import 'lifecycle_demo_state.dart';
import 'lifecycle_demo_events.dart';

/// Demo bloc showing ScopeLifecycleBloc's cleanup capabilities.
///
/// This bloc simulates parallel async tasks and demonstrates how
/// ScopeLifecycleBloc's CleanupBarrier ensures proper cleanup when a
/// scope ends.
class LifecycleDemoBloc extends JuiceBloc<LifecycleDemoState> {
  final Random _random = Random();

  /// Active timers for task simulation.
  final Map<String, Timer> _taskTimers = {};

  /// The current demo scope.
  FeatureScope? _scope;

  /// Subscription to ScopeLifecycleBloc notifications.
  StreamSubscription? _lifecycleSubscription;

  /// Completer for cleanup completion.
  Completer<void>? _cleanupCompleter;

  LifecycleDemoBloc()
      : super(
          const LifecycleDemoState(),
          [
            // Use cases are simple - most logic is in the bloc itself
            () => UseCaseBuilder(
                  typeOfEvent: StartDemoEvent,
                  useCaseGenerator: () => _StartDemoUseCase(),
                ),
            () => UseCaseBuilder(
                  typeOfEvent: EndDemoEvent,
                  useCaseGenerator: () => _EndDemoUseCase(),
                ),
            () => UseCaseBuilder(
                  typeOfEvent: ToggleSlowCleanupEvent,
                  useCaseGenerator: () => _ToggleSlowCleanupUseCase(),
                ),
            () => UseCaseBuilder(
                  typeOfEvent: UpdateTaskProgressEvent,
                  useCaseGenerator: () => _UpdateTaskProgressUseCase(),
                ),
            () => UseCaseBuilder(
                  typeOfEvent: TaskCompletedEvent,
                  useCaseGenerator: () => _TaskCompletedUseCase(),
                ),
            () => UseCaseBuilder(
                  typeOfEvent: CancelAllTasksEvent,
                  useCaseGenerator: () => _CancelAllTasksUseCase(),
                ),
            () => UseCaseBuilder(
                  typeOfEvent: AddLogEvent,
                  useCaseGenerator: () => _AddLogUseCase(),
                ),
            () => UseCaseBuilder(
                  typeOfEvent: ScopeEndingEvent,
                  useCaseGenerator: () => _ScopeEndingUseCase(),
                ),
            () => UseCaseBuilder(
                  typeOfEvent: ScopeEndedEvent,
                  useCaseGenerator: () => _ScopeEndedUseCase(),
                ),
            () => UseCaseBuilder(
                  typeOfEvent: UpdateDemoStateEvent,
                  useCaseGenerator: () => _UpdateDemoStateUseCase(),
                ),
            () => UseCaseBuilder(
                  typeOfEvent: ResetDemoEvent,
                  useCaseGenerator: () => _ResetDemoUseCase(),
                ),
          ],
        ) {
    _subscribeToLifecycle();
  }

  /// Subscribe to ScopeLifecycleBloc notifications.
  void _subscribeToLifecycle() {
    if (!BlocScope.isRegistered<ScopeLifecycleBloc>()) return;

    final lifecycleBloc = BlocScope.get<ScopeLifecycleBloc>();
    _lifecycleSubscription = lifecycleBloc.notifications.listen((notification) {
      if (notification is ScopeEndingNotification &&
          notification.scopeName == 'lifecycle-demo') {
        // Register cleanup on the barrier
        _cleanupCompleter = Completer<void>();
        notification.barrier.add(_performCleanup());

        // Also add slow cleanup if toggled
        if (state.addSlowCleanup) {
          notification.barrier.add(Future.delayed(const Duration(seconds: 5)));
          send(AddLogEvent(
              message: 'Added 5s slow cleanup to CleanupBarrier'));
        }

        // Update UI to show "ending" state
        send(ScopeEndingEvent());
        send(AddLogEvent(
            message:
                'ScopeEndingNotification received - CleanupBarrier waiting for ${state.activeTaskCount} tasks'));
      } else if (notification is ScopeEndedNotification &&
          notification.scopeName == 'lifecycle-demo') {
        send(ScopeEndedEvent());
        send(AddLogEvent(
            message: notification.cleanupCompleted
                ? 'ScopeEndedNotification - All cleanup completed successfully'
                : 'ScopeEndedNotification - Cleanup TIMED OUT (barrier exceeded timeout)'));
      } else if (notification is ScopeStartedNotification &&
          notification.scopeName == 'lifecycle-demo') {
        send(AddLogEvent(message: 'ScopeStartedNotification - FeatureScope created (${notification.scopeId})'));
      }
    });
  }

  /// Perform cleanup - cancel all running tasks.
  Future<void> _performCleanup() async {
    send(CancelAllTasksEvent());
    // Small delay to let cancellation propagate visually
    await Future.delayed(const Duration(milliseconds: 100));
    _cleanupCompleter?.complete();
  }

  /// Start the demo with a new scope and tasks.
  Future<void> startDemo() async {
    if (state.scopeActive) return;

    // Create and start scope
    _scope = FeatureScope('lifecycle-demo');
    await _scope!.start();

    // Spawn 5-8 random tasks
    final taskCount = 5 + _random.nextInt(4);
    final tasks = <TaskInfo>[];

    for (var i = 0; i < taskCount; i++) {
      final duration = Duration(seconds: 2 + _random.nextInt(7));
      final task = TaskInfo(
        id: 'task_$i',
        name: _taskNames[i % _taskNames.length],
        progress: 0.0,
        status: TaskStatus.running,
        totalDuration: duration,
      );
      tasks.add(task);
      _startTaskTimer(task);
    }

    // Update state via internal event
    send(UpdateDemoStateEvent(
      tasks: tasks,
      scopeActive: true,
      scopeEnding: false,
    ));

    // Log the task spawn
    send(AddLogEvent(message: 'Spawned $taskCount simulated async tasks (2-8s each)'));
  }

  /// Start a timer to simulate task progress.
  void _startTaskTimer(TaskInfo task) {
    const updateInterval = Duration(milliseconds: 100);
    final totalUpdates = task.totalDuration.inMilliseconds ~/ 100;
    var updates = 0;

    _taskTimers[task.id] = Timer.periodic(updateInterval, (timer) {
      updates++;
      final progress = updates / totalUpdates;

      if (progress >= 1.0) {
        timer.cancel();
        _taskTimers.remove(task.id);
        send(TaskCompletedEvent(taskId: task.id));
      } else {
        send(UpdateTaskProgressEvent(taskId: task.id, progress: progress));
      }
    });
  }

  /// End the demo scope.
  Future<void> endDemo() async {
    if (!state.scopeActive || _scope == null) return;
    await _scope!.end();
    _scope = null;
  }

  /// Cancel all task timers.
  void cancelAllTimers() {
    for (final timer in _taskTimers.values) {
      timer.cancel();
    }
    _taskTimers.clear();
  }

  @override
  Future<void> close() async {
    cancelAllTimers();
    await _lifecycleSubscription?.cancel();
    await super.close();
  }
}

// Task name pool for variety
const _taskNames = [
  'Fetch user data',
  'Load images',
  'Sync settings',
  'Process queue',
  'Upload logs',
  'Parse response',
  'Validate cache',
  'Compress files',
];

// ============================================================================
// Use Cases
// ============================================================================

class _StartDemoUseCase extends BlocUseCase<LifecycleDemoBloc, StartDemoEvent> {
  @override
  Future<void> execute(StartDemoEvent event) async {
    await bloc.startDemo();
  }
}

class _EndDemoUseCase extends BlocUseCase<LifecycleDemoBloc, EndDemoEvent> {
  @override
  Future<void> execute(EndDemoEvent event) async {
    await bloc.endDemo();
  }
}

class _ToggleSlowCleanupUseCase
    extends BlocUseCase<LifecycleDemoBloc, ToggleSlowCleanupEvent> {
  @override
  Future<void> execute(ToggleSlowCleanupEvent event) async {
    emitUpdate(
      groupsToRebuild: {LifecycleDemoGroups.controls},
      newState: bloc.state.copyWith(addSlowCleanup: !bloc.state.addSlowCleanup),
    );
  }
}

class _UpdateTaskProgressUseCase
    extends BlocUseCase<LifecycleDemoBloc, UpdateTaskProgressEvent> {
  @override
  Future<void> execute(UpdateTaskProgressEvent event) async {
    final tasks = bloc.state.tasks.map((t) {
      if (t.id == event.taskId) {
        return t.copyWith(progress: event.progress);
      }
      return t;
    }).toList();

    emitUpdate(
      groupsToRebuild: {LifecycleDemoGroups.tasks},
      newState: bloc.state.copyWith(tasks: tasks),
    );
  }
}

class _TaskCompletedUseCase
    extends BlocUseCase<LifecycleDemoBloc, TaskCompletedEvent> {
  @override
  Future<void> execute(TaskCompletedEvent event) async {
    final tasks = bloc.state.tasks.map((t) {
      if (t.id == event.taskId) {
        return t.copyWith(progress: 1.0, status: TaskStatus.completed);
      }
      return t;
    }).toList();

    emitUpdate(
      groupsToRebuild: {LifecycleDemoGroups.tasks},
      newState: bloc.state.copyWith(tasks: tasks),
    );
  }
}

class _CancelAllTasksUseCase
    extends BlocUseCase<LifecycleDemoBloc, CancelAllTasksEvent> {
  @override
  Future<void> execute(CancelAllTasksEvent event) async {
    final activeCount = bloc.state.activeTaskCount;
    bloc.cancelAllTimers();

    final tasks = bloc.state.tasks.map((t) {
      if (t.isActive) {
        return t.copyWith(status: TaskStatus.canceled);
      }
      return t;
    }).toList();

    emitUpdate(
      groupsToRebuild: {LifecycleDemoGroups.tasks},
      newState: bloc.state.copyWith(tasks: tasks),
    );

    // Log the cancellation
    if (activeCount > 0) {
      bloc.send(AddLogEvent(message: 'Canceled $activeCount in-flight tasks via CleanupBarrier'));
    }
  }
}

class _AddLogUseCase extends BlocUseCase<LifecycleDemoBloc, AddLogEvent> {
  @override
  Future<void> execute(AddLogEvent event) async {
    emitUpdate(
      groupsToRebuild: {LifecycleDemoGroups.log},
      newState: bloc.state.withLog(event.message),
    );
  }
}

class _ScopeEndingUseCase
    extends BlocUseCase<LifecycleDemoBloc, ScopeEndingEvent> {
  @override
  Future<void> execute(ScopeEndingEvent event) async {
    emitUpdate(
      groupsToRebuild: {LifecycleDemoGroups.controls},
      newState: bloc.state.copyWith(scopeEnding: true),
    );
  }
}

class _ScopeEndedUseCase
    extends BlocUseCase<LifecycleDemoBloc, ScopeEndedEvent> {
  @override
  Future<void> execute(ScopeEndedEvent event) async {
    // Show "ended" state briefly
    emitUpdate(
      groupsToRebuild: LifecycleDemoGroups.all,
      newState: bloc.state.copyWith(
        scopeActive: false,
        scopeEnding: false,
        scopeEnded: true,
      ),
    );

    // Reset after 2 seconds so user can see the "Ended" phase
    await Future.delayed(const Duration(seconds: 2));
    bloc.send(ResetDemoEvent());
  }
}

class _ResetDemoUseCase
    extends BlocUseCase<LifecycleDemoBloc, ResetDemoEvent> {
  @override
  Future<void> execute(ResetDemoEvent event) async {
    emitUpdate(
      groupsToRebuild: LifecycleDemoGroups.all,
      newState: bloc.state.copyWith(
        tasks: [],
        scopeEnded: false,
      ),
    );
    bloc.send(AddLogEvent(message: 'Demo reset - ready for next run'));
  }
}

class _UpdateDemoStateUseCase
    extends BlocUseCase<LifecycleDemoBloc, UpdateDemoStateEvent> {
  @override
  Future<void> execute(UpdateDemoStateEvent event) async {
    emitUpdate(
      groupsToRebuild: LifecycleDemoGroups.all,
      newState: bloc.state.copyWith(
        tasks: event.tasks?.cast<TaskInfo>(),
        scopeActive: event.scopeActive,
        scopeEnding: event.scopeEnding,
      ),
    );
  }
}
