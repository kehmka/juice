# Building Your First Juice App: Counter Tutorial

This step-by-step tutorial will guide you through building a counter application using Juice. You'll learn core concepts like blocs, use cases, and reactive widgets while building a fully functional app.

## What We're Building

A counter app that:
- Displays a number
- Has buttons to increment and decrement the count
- Includes a reset button
- Updates UI efficiently
- Uses proper architecture patterns

## Prerequisites

- Flutter development environment set up
- Basic understanding of Flutter widgets
- Juice package installed in your project

## Project Structure

We'll create these files:
```
lib/
├── counter/
│   ├── counter_bloc.dart      # Bloc implementation
│   ├── counter_state.dart     # State definition
│   ├── counter_events.dart    # Event definitions
│   ├── use_cases/
│   │   ├── increment_use_case.dart
│   │   ├── decrement_use_case.dart
│   │   └── reset_use_case.dart
│   ├── widgets/
│   │   ├── counter_widget.dart
│   │   ├── counter_buttons.dart
│   │   └── counter_page.dart
│   └── counter.dart          # Barrel file for exports
└── main.dart
```

Create `counter.dart` as a barrel file to export all counter-related components:

```dart
// State and Events
export 'counter_state.dart';
export 'counter_events.dart';
export 'counter_bloc.dart';

// Widgets
export 'widgets/counter_widget.dart';
export 'widgets/counter_buttons.dart';
export 'widgets/counter_page.dart';
```

This barrel file pattern:
- Provides a single import point for counter feature
- Makes imports cleaner in other files
- Helps manage feature boundaries
- Makes refactoring easier

## Things we should NOT export:

- Use cases (very rarely would you want to expore a usecase)
- Internal widgets 
- Internal models 
- Internal services - These should be accessed through the bloc

## The key principles are:

- Export only what other features need to interact with your feature
- Keep implementation details private to the feature
- Force interaction through the bloc's public interface
- Only expose models that are truly shared (if so, consider moving them out of the feature into a share folder)
- Expose pages needed for navigation

This helps maintain better encapsulation and makes refactoring easier since you have fewer public dependencies to manage.

## Step 1: State Definition

First, let's define what state our counter app needs to track. Create `counter_state.dart`:

```dart
import 'package:juice/juice.dart';

class CounterState extends BlocState {
  final int count;

  CounterState({required this.count});

  // Creates a copy of the current state with updated fields
  CounterState copyWith({int? count}) {
    return CounterState(count: count ?? this.count);
  }

  @override
  String toString() => 'CounterState(count: $count)';
}
```

Key points:
- State class extends `BlocState`
- Uses immutable fields
- Implements `copyWith` for state updates
- Override `toString` for debugging

## Step 2: Events

Next, define the events that can change our counter. Create `counter_events.dart`:

```dart
import 'package:juice/juice.dart';

class IncrementEvent extends EventBase {
  IncrementEvent();
}

class DecrementEvent extends EventBase {
  DecrementEvent();
}

class ResetEvent extends EventBase {
  ResetEvent();
}
```

Key points:
- Each event extends `EventBase`
- Events represent user actions
- Keep events simple and focused

## Step 3: Use Cases

Now we'll create use cases to handle each event. Each use case is responsible for one specific operation.

### Increment Use Case
Create `increment_use_case.dart`:

```dart
import 'package:juice/juice.dart';
import '../counter.dart';

class IncrementUseCase extends BlocUseCase<CounterBloc, IncrementEvent> {
  @override
  Future<void> execute(IncrementEvent event) async {
    final newState = bloc.state.copyWith(count: bloc.state.count + 1);
    emitUpdate(groupsToRebuild: {"counter"}, newState: newState);
  }
}
```

### Decrement Use Case
Create `decrement_use_case.dart`:

```dart
import 'package:juice/juice.dart';
import '../counter_bloc.dart';
import '../counter_events.dart';

class DecrementUseCase extends BlocUseCase<CounterBloc, DecrementEvent> {
  @override
  Future<void> execute(DecrementEvent event) async {
    final newState = bloc.state.copyWith(count: bloc.state.count - 1);
    emitUpdate(groupsToRebuild: {"counter"}, newState: newState);
  }
}
```

### Reset Use Case
Create `reset_use_case.dart`:

```dart
import 'package:juice/juice.dart';
import '../counter_bloc.dart';
import '../counter_events.dart';

class ResetUseCase extends BlocUseCase<CounterBloc, ResetEvent> {
  @override
  Future<void> execute(ResetEvent event) async {
    final newState = bloc.state.copyWith(count: 0);
    emitUpdate(groupsToRebuild: {"counter"}, newState: newState);
  }
}
```

Key points:
- Each use case extends `BlocUseCase`
- Type parameters specify bloc and event type
- Use `emitUpdate` to update state
- Specify rebuild groups for efficient updates

## Step 4: Counter Bloc

Create the bloc that coordinates our use cases. Create `counter_bloc.dart`:

```dart
import 'package:juice/juice.dart';
import 'counter_state.dart';
import 'counter_events.dart';
import 'use_cases/increment_use_case.dart';
import 'use_cases/decrement_use_case.dart';
import 'use_cases/reset_use_case.dart';

class CounterBloc extends JuiceBloc<CounterState> {
  CounterBloc()
      : super(
          CounterState(count: 0),
          [
            () => UseCaseBuilder(
                typeOfEvent: IncrementEvent,
                useCaseGenerator: () => IncrementUseCase()),
            () => UseCaseBuilder(
                typeOfEvent: DecrementEvent,
                useCaseGenerator: () => DecrementUseCase()),
            () => UseCaseBuilder(
                typeOfEvent: ResetEvent,
                useCaseGenerator: () => ResetUseCase()),
          ],
          [],
        );
}
```

Key points:
- Extends `JuiceBloc` with your state type
- Provides initial state
- Registers use cases with their events
- Third parameter is for aviators (navigation handlers)

## Step 5: Widgets

Now let's create the UI components. We'll split them into two widgets for better control over rebuilds.

### Counter Display
Create `counter_widget.dart`:

```dart
import 'package:juice/juice.dart';
import '../counter.dart';

class CounterWidget extends StatelessJuiceWidget<CounterBloc> {
  CounterWidget({super.key, super.groups = const {"counter"}});

  @override
  Widget onBuild(BuildContext context, StreamStatus status) {
    return Text(
      'Count: ${bloc.state.count}',
      style: const TextStyle(fontSize: 32),
    );
  }
}
```

### Counter Buttons
Create `counter_buttons.dart`:

```dart
class CounterButtons extends StatelessJuiceWidget<CounterBloc> {
  CounterButtons({super.key, super.groups = optOutOfRebuilds});

  @override
  Widget onBuild(BuildContext context, StreamStatus status) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        ElevatedButton(
          onPressed: () => bloc.send(IncrementEvent()),
          child: const Text('+'),
        ),
        const SizedBox(width: 16),
        ElevatedButton(
          onPressed: () => bloc.send(DecrementEvent()),
          child: const Text('-'),
        ),
        const SizedBox(width: 16),
        ElevatedButton(
          onPressed: () => bloc.send(ResetEvent()),
          child: const Text('Reset'),
        ),
      ],
    );
  }
}
```

Key points:
- Extend `StatelessJuiceWidget` with your bloc type
- Specify rebuild groups
- Buttons opt out of rebuilds since they never change
- Access state through `bloc.state`
- Send events using `bloc.send`

## Step 6: Counter Page

Create `counter_page.dart` to bring it all together:

```dart
import 'package:flutter/material.dart';
import 'package:juice/juice.dart';
import 'counter/counter.dart';

class CounterPage extends StatelessWidget {
  const CounterPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Counter Example')),
      body: Center(
        child: CounterWidget(),
      ),
      floatingActionButton: CounterButtons(),
    );
  }
}
```

## Step 7: Initialize Juice and Register Blocs

First, create a `bloc_registration.dart` file to organize bloc registration:

```dart
import 'package:juice/juice.dart';
import 'counter/bloc/counter_bloc.dart';

class BlocRegistry {
  static void initialize() {
    // Register bloc factories
    BlocScope.registerFactory<CounterBloc>(() => CounterBloc());
  }
}
```

Then in your `main.dart`, initialize Juice and register blocs:

```dart
void main() {
  // Set up bloc resolution
  GlobalBlocResolver().resolver = BlocResolver();
  
  // Register blocs
  BlocRegistry.initialize();
  
  runApp(MaterialApp(
    home: CounterPage(),
  ));
}
```

Key points about bloc registration:
- Use `BlocScope.registerFactory` to register bloc creation functions
- This tells Juice how to create bloc instances when requested
- Registration must happen before any widgets try to access blocs
- Each bloc type needs to be registered exactly once
- The bloc instance will be created lazily when first requested

## Testing Your App

1. Run the app
2. Press + to increment
3. Press - to decrement
4. Press Reset to set count to 0

## Key Concepts Learned

- **State Management**: Defined immutable state with `BlocState`
- **Events**: Created events for user actions
- **Use Cases**: Implemented business logic in focused use cases
- **Bloc**: Coordinated use cases and state
- **Widgets**: Built reactive UI with `StatelessJuiceWidget`
- **Efficient Updates**: Used group-based rebuilds

## Next Steps

Now that you understand the basics, try:
1. Adding validation (prevent negative numbers)
2. Implementing undo/redo
3. Adding persistence
4. Creating an animated counter display

## Common Questions

**Q: Why split into separate use cases?**  
A: Each use case is focused and testable. This becomes more valuable as operations get more complex.

**Q: Why separate the display and buttons?**  
A: This lets us optimize rebuilds. The buttons never change, so they opt out of rebuilds entirely.

**Q: When do I use StreamStatus?**  
A: Use it for UI state decisions (loading, error states) but always access data through `bloc.state`.

## Best Practices Demonstrated

1. Clean separation of concerns
2. Immutable state
3. Single-responsibility use cases
4. Efficient UI updates
5. Clear event handling
6. Type-safe bloc access
