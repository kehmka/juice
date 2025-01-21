# Advanced Use Cases

This guide showcases sophisticated use case patterns that demonstrate the full power of Juice's architecture.

## Real-Time Data Synchronization

Maintain consistent state across multiple data sources:

```dart
class SyncDatabaseUseCase extends BlocUseCase<DataBloc, SyncEvent> {
  final WebSocketConnection _socket;
  final Database _db;
  StreamSubscription? _subscription;
  
  @override
  Future<void> execute(SyncEvent event) async {
    try {
      emitWaiting(groupsToRebuild: {"sync_status"});
      
      // Setup realtime sync
      _subscription = _socket.messages.listen((update) async {
        // Optimistically update UI
        emitUpdate(
          newState: DataState.updated(update),
          groupsToRebuild: {"data_view"}
        );
        
        try {
          // Persist to local database
          await _db.transaction((txn) async {
            await txn.update(update);
          });
        } catch (e, stack) {
          // Revert optimistic update
          logError(e, stack);
          emitUpdate(
            newState: await _db.getCurrentState(),
            groupsToRebuild: {"data_view"}
          );
        }
      });
      
      emitUpdate(
        newState: DataState.syncing(),
        groupsToRebuild: {"sync_status"}
      );
    } catch (e, stack) {
      logError(e, stack);
      emitFailure(groupsToRebuild: {"sync_status"});
    }
  }
  
  @override
  Future<void> close() async {
    await _subscription?.cancel();
    await _socket.close();
    super.close();
  }
}
```

## Multi-Step Form Handling

Complex form with validation and state persistence:

```dart
class ComplexFormUseCase extends BlocUseCase<FormBloc, FormEvent> {
  final FormValidator _validator;
  final FormStorage _storage;
  
  @override
  Future<void> execute(FormEvent event) async {
    if (event is FormUpdateEvent) {
      await _handleUpdate(event);
    } else if (event is FormSubmitEvent) {
      await _handleSubmit(event);
    } else if (event is FormSaveEvent) {
      await _handleSave(event);
    }
  }
  
  Future<void> _handleUpdate(FormUpdateEvent event) async {
    try {
      // Validate field
      final validationResult = await _validator.validateField(
        event.fieldId,
        event.value
      );
      
      if (!validationResult.isValid) {
        emitUpdate(
          newState: FormState.fieldError(
            event.fieldId,
            validationResult.error
          ),
          groupsToRebuild: {"field_${event.fieldId}", "submit_button"}
        );
        return;
      }
      
      // Update form state
      emitUpdate(
        newState: FormState.fieldUpdated(
          event.fieldId,
          event.value
        ),
        groupsToRebuild: {"field_${event.fieldId}", "submit_button"}
      );
      
      // Save progress
      await _storage.saveProgress(bloc.state);
      
    } catch (e, stack) {
      logError(e, stack);
      emitFailure(groupsToRebuild: {"field_${event.fieldId}"});
    }
  }
  
  Future<void> _handleSubmit(FormSubmitEvent event) async {
    try {
      emitWaiting(groupsToRebuild: {"submit_status"});
      
      // Validate all fields
      final validationResult = await _validator.validateAll(bloc.state);
      if (!validationResult.isValid) {
        emitUpdate(
          newState: FormState.withErrors(validationResult.errors),
          groupsToRebuild: {"form_fields", "submit_status"}
        );
        return;
      }
      
      // Submit form
      await submitForm(bloc.state);
      
      emitUpdate(
        newState: FormState.submitted(),
        groupsToRebuild: {"form_status"},
        aviatorName: "form_complete"
      );
    } catch (e, stack) {
      logError(e, stack);
      emitFailure(groupsToRebuild: {"submit_status"});
    }
  }
}
```

## Background Task Management

Handle long-running tasks with progress updates:

```dart
class BackgroundTaskUseCase extends BlocUseCase<TaskBloc, StartTaskEvent> {
  final TaskQueue _queue;
  final Map<String, StreamSubscription> _taskSubscriptions = {};
  
  @override
  Future<void> execute(StartTaskEvent event) async {
    try {
      // Add task to queue
      final taskId = await _queue.enqueue(event.task);
      
      // Track task progress
      _taskSubscriptions[taskId] = _queue.taskProgress(taskId).listen(
        (progress) {
          emitUpdate(
            newState: TaskState.progress(taskId, progress),
            groupsToRebuild: {"task_$taskId"}
          );
        },
        onError: (error, stack) {
          logError(error, stack);
          emitUpdate(
            newState: TaskState.failed(taskId, error.toString()),
            groupsToRebuild: {"task_$taskId"}
          );
        },
        onDone: () {
          emitUpdate(
            newState: TaskState.completed(taskId),
            groupsToRebuild: {"task_$taskId", "task_list"}
          );
          _taskSubscriptions.remove(taskId)?.cancel();
        }
      );
      
      // Update queue status
      emitUpdate(
        newState: TaskState.queued(taskId),
        groupsToRebuild: {"task_list"}
      );
    } catch (e, stack) {
      logError(e, stack);
      emitFailure(groupsToRebuild: {"task_list"});
    }
  }
  
  @override
  Future<void> close() async {
    for (final sub in _taskSubscriptions.values) {
      await sub.cancel();
    }
    _taskSubscriptions.clear();
    await _queue.close();
    super.close();
  }
}
```

## Cached Data Management

Smart caching with background refresh:

```dart
class CachedDataUseCase extends BlocUseCase<DataBloc, FetchDataEvent> {
  final Cache _cache;
  final ApiClient _api;
  Timer? _refreshTimer;
  
  @override
  Future<void> execute(FetchDataEvent event) async {
    try {
      // Check cache first
      final cachedData = await _cache.get(event.key);
      if (cachedData != null) {
        emitUpdate(
          newState: DataState.fromCache(cachedData),
          groupsToRebuild: {"data_view"}
        );
      } else {
        emitWaiting(groupsToRebuild: {"loading_status"});
      }
      
      // Setup background refresh
      _refreshTimer?.cancel();
      _refreshTimer = Timer.periodic(
        Duration(minutes: 5),
        (_) => _refreshData(event.key)
      );
      
      // Fetch fresh data
      await _refreshData(event.key);
      
    } catch (e, stack) {
      logError(e, stack);
      if (cachedData == null) {
        emitFailure(groupsToRebuild: {"loading_status"});
      }
    }
  }
  
  Future<void> _refreshData(String key) async {
    try {
      final freshData = await _api.fetch(key);
      await _cache.set(key, freshData);
      
      emitUpdate(
        newState: DataState.fromApi(freshData),
        groupsToRebuild: {"data_view"}
      );
    } catch (e, stack) {
      logError(e, stack);
      // Don't emit failure if we have cached data
    }
  }
  
  @override
  Future<void> close() async {
    _refreshTimer?.cancel();
    await _cache.close();
    super.close();
  }
}
```

## Multi-Device Sync

Keep state synchronized across devices:

```dart
class DeviceSyncUseCase extends BlocUseCase<SyncBloc, SyncEvent> {
  final DeviceSync _sync;
  final LocalStore _store;
  StreamSubscription? _subscription;
  
  @override
  Future<void> execute(SyncEvent event) async {
    try {
      emitWaiting(groupsToRebuild: {"sync_status"});
      
      // Initialize local state
      final localState = await _store.getState();
      emitUpdate(
        newState: SyncState.local(localState),
        groupsToRebuild: {"data_view"}
      );
      
      // Listen for remote changes
      _subscription = _sync.changes.listen(
        (change) async {
          try {
            // Apply remote change
            final newState = await _applyChange(change);
            
            // Store locally
            await _store.setState(newState);
            
            // Update UI
            emitUpdate(
              newState: SyncState.synced(newState),
              groupsToRebuild: {"data_view", "sync_status"}
            );
          } catch (e, stack) {
            logError(e, stack);
            emitUpdate(
              newState: SyncState.conflict(change),
              groupsToRebuild: {"sync_status"}
            );
          }
        },
        onError: (error, stack) {
          logError(error, stack);
          emitFailure(groupsToRebuild: {"sync_status"});
        }
      );
      
      // Mark as ready
      emitUpdate(
        newState: SyncState.ready(localState),
        groupsToRebuild: {"sync_status"}
      );
    } catch (e, stack) {
      logError(e, stack);
      emitFailure(groupsToRebuild: {"sync_status"});
    }
  }
  
  Future<State> _applyChange(Change change) async {
    // Merge strategy here
    return mergedState;
  }
  
  @override
  Future<void> close() async {
    await _subscription?.cancel();
    await _sync.close();
    await _store.close();
    super.close();
  }
}
```

## Feature Flag Management

Control feature rollout:

```dart
class FeatureFlagUseCase extends BlocUseCase<FeatureBloc, UpdateFlagsEvent> {
  final FeatureConfig _config;
  final Analytics _analytics;
  StreamSubscription? _configSubscription;
  
  @override
  Future<void> execute(UpdateFlagsEvent event) async {
    try {
      emitWaiting(groupsToRebuild: {"feature_status"});
      
      // Load initial config
      final config = await _config.load();
      
      // Setup config updates
      _configSubscription = _config.updates.listen(
        (newConfig) async {
          // Determine changes
          final changes = _determineChanges(bloc.state.config, newConfig);
          
          // Apply progressively to avoid UI jumps
          for (final change in changes) {
            emitUpdate(
              newState: FeatureState.updated(
                bloc.state.config.copyWith(
                  feature: change.feature,
                  enabled: change.enabled
                )
              ),
              groupsToRebuild: {"feature_${change.feature}"}
            );
            
            // Track feature state
            await _analytics.trackFeature(
              change.feature,
              change.enabled
            );
            
            // Small delay between updates
            await Future.delayed(Duration(milliseconds: 100));
          }
        },
        onError: (error, stack) {
          logError(error, stack);
          emitFailure(groupsToRebuild: {"feature_status"});
        }
      );
      
      // Update initial state
      emitUpdate(
        newState: FeatureState.initial(config),
        groupsToRebuild: {"feature_list"}
      );
    } catch (e, stack) {
      logError(e, stack);
      emitFailure(groupsToRebuild: {"feature_status"});
    }
  }
  
  List<FeatureChange> _determineChanges(
    FeatureConfig oldConfig,
    FeatureConfig newConfig
  ) {
    // Change detection logic here
    return changes;
  }
  
  @override
  Future<void> close() async {
    await _configSubscription?.cancel();
    await _config.close();
    super.close();
  }
}
```

## Complex Data Processing

Handle complex data transformations:

```dart
class DataProcessingUseCase extends BlocUseCase<ProcessBloc, ProcessEvent> {
  final DataProcessor _processor;
  final ProcessCache _cache;
  CancelableOperation? _currentOperation;
  
  @override
  Future<void> execute(ProcessEvent event) async {
    if (event is CancellableEvent && event.isCancelled) {
      await _currentOperation?.cancel();
      emitCancel(groupsToRebuild: {"process_status"});
      return;
    }
    
    try {
      emitWaiting(groupsToRebuild: {"process_status"});
      
      // Check cache
      final cached = await _cache.get(event.dataId);
      if (cached != null) {
        emitUpdate(
          newState: ProcessState.fromCache(cached),
          groupsToRebuild: {"results_view"}
        );
      }
      
      // Start processing
      _currentOperation = CancelableOperation.fromFuture(
        _processor.process(
          event.data,
          onProgress: (progress) {
            emitUpdate(
              newState: ProcessState.progress(progress),
              groupsToRebuild: {"progress_bar"}
            );
          }
        )
      );
      
      final result = await _currentOperation?.value;
      if (result == null) return; // Cancelled
      
      // Cache result
      await _cache.set(event.dataId, result);
      
      // Update UI
      emitUpdate(
        newState: ProcessState.completed(result),
        groupsToRebuild: {"results_view", "process_status"}
      );
    } catch (e, stack) {
      logError(e, stack);
      emitFailure(groupsToRebuild: {"process_status"});
    } finally {
      _currentOperation = null;
    }
  }
  
  @override
  Future<void> close() async {
    await _currentOperation?.cancel();
    await _cache.close();
    super.close();
  }
}
```

## Best Practices

1. **Resource Management**
   - Always clean up resources in close()
   - Cancel operations properly
   - Close streams and subscriptions
   - Release expensive resources

2. **State Updates**
   - Use targeted rebuilds
   - Batch related updates
   - Consider UI impact
   - Handle edge cases

3. **Error Handling**
   - Log errors with context
   - Provide recovery paths
   - Maintain consistent state
   - Clean up on failure

4. **Performance**
   - Cache expensive operations
   - Batch updates when possible
   - Use debounced operations
   - Optimize rebuild groups
   - Leverage lazy initialization
   - Implement pagination
   - Profile memory usage

5. **State Consistency**
   - Validate state transitions
   - Handle race conditions
   - Implement rollback mechanisms
   - Version state changes
   - Maintain audit trails
   - Handle concurrent updates

6. **Testing Considerations**
   - Mock external dependencies
   - Test error recovery
   - Verify resource cleanup
   - Test cancellation
   - Profile performance
   - Test concurrency
   - Validate state consistency

7. **Monitoring & Debugging**
   - Add detailed logging
   - Track performance metrics
   - Monitor resource usage
   - Implement health checks
   - Add debug utilities
   - Track usage patterns

## Example Implementation

Here's a complete example incorporating these best practices:

```dart
class RobustProcessingUseCase extends BlocUseCase<ProcessBloc, ProcessEvent> {
  final Processor _processor;
  final Cache _cache;
  final Monitor _monitor;
  final StateValidator _validator;
  
  Timer? _debounceTimer;
  StreamSubscription? _processSub;
  CancelableOperation? _currentOp;
  final _pendingUpdates = <Update>[];
  
  @override
  Future<void> execute(ProcessEvent event) async {
    try {
      // Start monitoring
      final span = _monitor.startSpan('process_operation');
      
      // Validate state transition
      if (!_validator.canTransition(bloc.state, event)) {
        throw StateError('Invalid transition');
      }
      
      // Check cache
      final cached = await _cache.get(event.id);
      if (cached != null && !cached.isStale) {
        emitUpdate(
          newState: ProcessState.fromCache(cached),
          groupsToRebuild: {"results"}
        );
        return;
      }
      
      // Show loading state
      emitWaiting(groupsToRebuild: {"status"});
      
      // Debounce rapid updates
      _debounceTimer?.cancel();
      _debounceTimer = Timer(Duration(milliseconds: 100), () async {
        try {
          // Start processing
          _currentOp = CancelableOperation.fromFuture(
            _processor.process(
              event.data,
              onProgress: _handleProgress,
              onUpdate: _queueUpdate,
            )
          );
          
          final result = await _currentOp?.value;
          if (result == null) return; // Cancelled
          
          // Validate result
          if (!_validator.isValid(result)) {
            throw ValidationError('Invalid result state');
          }
          
          // Cache result
          await _cache.set(event.id, result);
          
          // Batch emit pending updates
          if (_pendingUpdates.isNotEmpty) {
            _emitBatchUpdate();
          }
          
          // Final update
          emitUpdate(
            newState: ProcessState.completed(result),
            groupsToRebuild: {"results", "status"}
          );
          
        } catch (e, stack) {
          _handleError(e, stack);
        } finally {
          span.end();
        }
      });
      
    } catch (e, stack) {
      _handleError(e, stack);
    }
  }
  
  void _handleProgress(Progress progress) {
    // Queue progress update
    _queueUpdate(Update(
      type: UpdateType.progress,
      data: progress,
      groups: {"progress"}
    ));
  }
  
  void _queueUpdate(Update update) {
    _pendingUpdates.add(update);
    
    // Batch emit if queue gets too large
    if (_pendingUpdates.length >= 10) {
      _emitBatchUpdate();
    }
  }
  
  void _emitBatchUpdate() {
    if (_pendingUpdates.isEmpty) return;
    
    // Combine updates
    final combinedState = _pendingUpdates.fold(
      bloc.state,
      (state, update) => state.apply(update)
    );
    
    // Combine rebuild groups
    final groups = _pendingUpdates
      .expand((u) => u.groups)
      .toSet();
    
    // Emit combined update
    emitUpdate(
      newState: combinedState,
      groupsToRebuild: groups
    );
    
    _pendingUpdates.clear();
  }
  
  void _handleError(Object error, StackTrace stack) {
    // Log error with context
    logError(
      error,
      stack,
      context: {
        'state': bloc.state,
        'pendingUpdates': _pendingUpdates.length,
        'hasCurrent': _currentOp != null,
      }
    );
    
    // Clean up
    _currentOp?.cancel();
    _pendingUpdates.clear();
    
    // Notify failure
    emitFailure(
      newState: ProcessState.error(error),
      groupsToRebuild: {"status", "error"}
    );
  }
  
  @override
  Future<void> close() async {
    _debounceTimer?.cancel();
    await _processSub?.cancel();
    await _currentOp?.cancel();
    _pendingUpdates.clear();
    await _cache.close();
    super.close();
  }
}
```

This example demonstrates several advanced patterns:

### 1. Resource Cleanup
The use case properly manages all resources to prevent leaks:
```dart
@override
Future<void> close() async {
  _debounceTimer?.cancel();      // Cancel timers
  await _processSub?.cancel();   // Clean up subscriptions
  await _currentOp?.cancel();    // Cancel in-flight operations
  _pendingUpdates.clear();       // Clear queued updates
  await _cache.close();          // Close external resources
  super.close();                 // Call parent cleanup
}
```
This ensures:
- No memory leaks from uncancelled subscriptions
- Proper cleanup of external resources
- Cancellation of pending operations
- Clear final state

### 2. State Validation
The use case validates state transitions and results:
```dart
// Validate state transition
if (!_validator.canTransition(bloc.state, event)) {
  throw StateError('Invalid transition');
}

// Validate result
if (!_validator.isValid(result)) {
  throw ValidationError('Invalid result state');
}
```
This provides:
- Consistent state transitions
- Data integrity checks
- Early error detection
- Clear validation boundaries

### 3. Error Handling
Comprehensive error handling with context and recovery:
```dart
void _handleError(Object error, StackTrace stack) {
  // Log with rich context
  logError(
    error,
    stack,
    context: {
      'state': bloc.state,
      'pendingUpdates': _pendingUpdates.length,
      'hasCurrent': _currentOp != null,
    }
  );
  
  // Clean up resources
  _currentOp?.cancel();
  _pendingUpdates.clear();
  
  // Update UI with error
  emitFailure(
    newState: ProcessState.error(error),
    groupsToRebuild: {"status", "error"}
  );
}
```
Features:
- Contextual error logging
- Resource cleanup on error
- Clear error state communication
- Recovery path handling

### 4. Performance Optimization
Multiple strategies to optimize performance:
```dart
// Debounce rapid updates
_debounceTimer?.cancel();
_debounceTimer = Timer(Duration(milliseconds: 100), () async {
  // Processing code
});

// Cache results
final cached = await _cache.get(event.id);
if (cached != null && !cached.isStale) {
  emitUpdate(
    newState: ProcessState.fromCache(cached),
    groupsToRebuild: {"results"}
  );
  return;
}

// Targeted rebuilds
emitUpdate(
  newState: newState,
  groupsToRebuild: {"specific_component"}  // Only rebuild what changed
);
```
This provides:
- Reduced unnecessary processing
- Faster response times
- Efficient UI updates
- Resource reuse

### 5. Monitoring
Built-in monitoring and metrics:
```dart
// Performance monitoring
final span = _monitor.startSpan('process_operation');
try {
  // Operation code
} finally {
  span.end();  // Record duration
}

// State tracking
logState('Updating with batch size: ${_pendingUpdates.length}');

// Resource monitoring
log('Cache stats', context: {
  'size': _cache.size,
  'hits': _cache.hits,
  'misses': _cache.misses
});
```
Features:
- Performance tracking
- Resource usage monitoring
- Operation metrics
- Debug information

### 6. Batched Updates
Efficient handling of multiple updates:
```dart
void _queueUpdate(Update update) {
  _pendingUpdates.add(update);
  
  // Batch emit if queue gets too large
  if (_pendingUpdates.length >= 10) {
    _emitBatchUpdate();
  }
}

void _emitBatchUpdate() {
  if (_pendingUpdates.isEmpty) return;
  
  // Combine states and rebuild groups
  final combinedState = _pendingUpdates.fold(
    bloc.state,
    (state, update) => state.apply(update)
  );
  
  final groups = _pendingUpdates
    .expand((u) => u.groups)
    .toSet();
  
  // Single emission for multiple updates
  emitUpdate(
    newState: combinedState,
    groupsToRebuild: groups
  );
}
```
Benefits:
- Reduced UI updates
- Efficient state transitions
- Better performance
- Smoother UI experience

### 7. Progress Tracking
Detailed progress monitoring:
```dart
void _handleProgress(Progress progress) {
  _queueUpdate(Update(
    type: UpdateType.progress,
    data: progress,
    groups: {"progress"}
  ));
  
  // Monitor rate
  _progressRate.addSample(progress.value);
  
  // Estimate completion
  final eta = _progressRate.estimateCompletion(
    progress.value,
    progress.total
  );
  
  log('Progress update', context: {
    'progress': progress.value,
    'total': progress.total,
    'rate': _progressRate.current,
    'eta': eta
  });
}
```
Features:
- Real-time progress updates
- Rate monitoring
- ETA calculation
- Progress persistence

### 8. Caching
Smart caching strategy:
```dart
class SmartCache {
  final _cache = <String, CacheEntry>{};
  
  Future<T?> get<T>(String key) async {
    final entry = _cache[key];
    
    // Check staleness
    if (entry?.isStale ?? true) {
      return null;
    }
    
    // Update access metrics
    entry!.recordAccess();
    
    // Perform background refresh if needed
    if (entry.shouldRefresh) {
      _scheduleRefresh(key);
    }
    
    return entry.value as T;
  }
  
  void _evictIfNeeded() {
    if (_cache.length <= maxSize) return;
    
    // LRU eviction
    final lru = _cache.entries
      .sorted((a, b) => a.lastAccess.compareTo(b.lastAccess))
      .first;
      
    _cache.remove(lru.key);
  }
}
```
Features:
- Staleness checking
- Background refresh
- LRU eviction
- Access metrics
- Type safety

### 9. Debugging Support
Rich debugging capabilities:
```dart
class DebugSupport {
  // State history
  final _stateHistory = <StateTransition>[];
  
  // Performance metrics
  final _metrics = <String, Metric>{};
  
  // Debug logging
  void logTransition(State oldState, State newState) {
    _stateHistory.add(StateTransition(
      oldState: oldState,
      newState: newState,
      timestamp: DateTime.now(),
      stackTrace: StackTrace.current
    ));
  }
  
  // Performance tracking
  void recordMetric(String name, double value) {
    _metrics.putIfAbsent(name, () => Metric(name))
      .addSample(value);
  }
  
  // Debug dump
  String getDiagnostics() {
    return {
      'states': _stateHistory.length,
      'metrics': _metrics,
      'memory': getMemoryStats(),
      'cache': getCacheStats()
    }.toString();
  }
}
```
Features:
- State history tracking
- Performance metrics
- Memory monitoring
- Diagnostic dumps
- Stack trace collection

These patterns work together to create robust, maintainable, and efficient use cases that can handle complex real-world requirements while remaining testable and debuggable.