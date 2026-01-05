# Memory Leak Detection

Juice provides built-in leak detection to help identify lifecycle management issues during development. The `LeakDetector` tracks bloc creations and lease acquisitions, alerting you to potential memory leaks.

## Overview

Common causes of memory leaks in Juice applications:

- **Unreleased leases** - Widgets that acquire a lease but forget to release it
- **Unclosed blocs** - Blocs that are never properly closed
- **Orphaned subscriptions** - Stream subscriptions that outlive their widgets

The LeakDetector helps identify these issues during development.

## Enabling Leak Detection

Enable leak detection early in your app's startup:

```dart
void main() {
  // Enable leak detection (only works in debug mode)
  BlocScope.enableLeakDetection();

  // Register your blocs
  registerBlocs();

  runApp(MyApp());
}
```

Or enable directly via LeakDetector:

```dart
import 'package:juice/juice.dart';

void main() {
  LeakDetector.enable();
  runApp(MyApp());
}
```

> **Note:** Leak detection only runs in debug mode (within `assert` blocks) and has no performance impact in release builds.

## What Gets Tracked

### Lease Tracking

When a widget acquires a bloc lease, LeakDetector records:
- Which bloc was leased
- When the lease was acquired
- The stack trace of the acquisition

When the lease is released, the tracking is cleared. Unreleased leases indicate potential leaks.

### Bloc Lifecycle Tracking

When a bloc is created, LeakDetector records:
- The bloc type
- When it was created
- The creation stack trace

When the bloc is closed, the tracking is cleared.

## Checking for Leaks

### Manual Check

```dart
// Check and print any leaks
if (LeakDetector.hasLeaks) {
  print(LeakDetector.getLeakReport());
}

// Or use checkForLeaks() which prints automatically
LeakDetector.checkForLeaks();
```

### At App Shutdown

```dart
class MyApp extends StatefulWidget {
  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.detached) {
      LeakDetector.checkForLeaks();
    }
  }
}
```

### In Tests

```dart
void main() {
  setUp(() {
    BlocScope.enableLeakDetection();
  });

  tearDown(() {
    // Check for leaks after each test
    final hasLeaks = LeakDetector.checkForLeaks();
    expect(hasLeaks, isFalse, reason: 'Test left unreleased resources');

    // Reset for next test
    LeakDetector.reset();
    BlocScope.endAll();
  });

  test('widget properly releases bloc lease', () async {
    // Test code...
  });
}
```

## Understanding Leak Reports

When leaks are detected, `getLeakReport()` provides detailed information:

```
=== Juice Leak Detection Report ===

UNRELEASED LEASES (2):
----------------------------------------

  CounterBloc (2 unreleased):
    Acquired at: 2024-01-15 10:30:45.123
    Stack trace:
      #0   BlocScope.lease (bloc_scope.dart:221)
      #1   StatelessJuiceWidget.initState (juice_widget.dart:45)
      #2   CounterDisplay.build (counter_display.dart:12)
      ...

    Acquired at: 2024-01-15 10:30:46.456
    Stack trace:
      #0   BlocScope.lease (bloc_scope.dart:221)
      #1   JuiceBuilder.initState (juice_builder.dart:78)
      ...

UNCLOSED BLOCS (1):
----------------------------------------

  TodoBloc:
    Created at: 2024-01-15 10:30:40.000
    Stack trace:
      #0   BlocScope._getOrCreate (bloc_scope.dart:275)
      #1   registerBlocs (bloc_registration.dart:15)
      ...

=== End Report ===
```

## Common Leak Patterns

### 1. Missing Dispose in StatefulWidget

```dart
// BAD - lease never released
class LeakyWidget extends StatefulWidget {
  @override
  State<LeakyWidget> createState() => _LeakyWidgetState();
}

class _LeakyWidgetState extends State<LeakyWidget> {
  late final BlocLease<CounterBloc> _lease;

  @override
  void initState() {
    super.initState();
    _lease = BlocScope.lease<CounterBloc>();
  }

  // Missing dispose!

  @override
  Widget build(BuildContext context) => ...;
}

// GOOD - lease properly released
class _GoodWidgetState extends State<GoodWidget> {
  late final BlocLease<CounterBloc> _lease;

  @override
  void initState() {
    super.initState();
    _lease = BlocScope.lease<CounterBloc>();
  }

  @override
  void dispose() {
    _lease.dispose();  // Release the lease
    super.dispose();
  }
}
```

### 2. Stream Subscription Without Cleanup

```dart
// BAD - subscription never cancelled
class _LeakyState extends State<LeakyWidget> {
  @override
  void initState() {
    super.initState();
    bloc.stream.listen((status) {
      // Handle status
    });
  }
}

// GOOD - subscription properly cancelled
class _GoodState extends State<GoodWidget> {
  StreamSubscription? _subscription;

  @override
  void initState() {
    super.initState();
    _subscription = bloc.stream.listen((status) {
      // Handle status
    });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}
```

### 3. Using StatelessJuiceWidget Correctly

StatelessJuiceWidget handles leases automatically - no action needed:

```dart
// GOOD - leases managed automatically
class CounterDisplay extends StatelessJuiceWidget<CounterBloc> {
  @override
  Widget onBuild(BuildContext context, StreamStatus status) {
    return Text('${bloc.state.count}');
  }
}
```

## API Reference

### LeakDetector

| Method | Description |
|--------|-------------|
| `enable()` | Enable leak detection (debug mode only) |
| `disable()` | Disable and clear all tracking |
| `hasLeaks` | Returns true if leaks detected |
| `checkForLeaks()` | Check and print leak report |
| `getLeakReport()` | Get detailed leak report string |
| `unreleasedLeaseCount` | Number of unreleased leases |
| `unclosedBlocCount` | Number of unclosed blocs |
| `reset()` | Clear all tracking data (for tests) |

### BlocScope

| Method | Description |
|--------|-------------|
| `enableLeakDetection()` | Convenience method to enable LeakDetector |

## Best Practices

1. **Enable early** - Call `enableLeakDetection()` before registering blocs

2. **Check in tests** - Add leak checks to your test tearDown

3. **Review stack traces** - Use the stack traces to find where leases are acquired

4. **Use Juice widgets** - `StatelessJuiceWidget` and `JuiceBuilder` manage leases automatically

5. **Dispose properly** - Always implement dispose in StatefulWidgets that acquire leases

## Integration with CI

Add leak detection to your test suite:

```dart
// test/leak_detection_test.dart
void main() {
  setUpAll(() {
    LeakDetector.enable();
  });

  tearDown(() {
    final report = LeakDetector.getLeakReport();
    LeakDetector.reset();

    if (LeakDetector.hasLeaks) {
      fail('Memory leak detected:\n$report');
    }
  });

  // Your tests here...
}
```
