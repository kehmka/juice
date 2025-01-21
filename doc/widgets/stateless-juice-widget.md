# StatelessJuiceWidget

## Overview

`StatelessJuiceWidget` is a specialized widget that connects your UI to Juice's reactive state management system. While a regular `StatelessWidget` is static and only rebuilds when its parameters change, a `StatelessJuiceWidget` automatically updates in response to state changes from its associated bloc.

## Key Features

- **Reactive Updates**: Automatically rebuilds when bloc state changes
- **Smart Rebuilding**: Precise control over which widgets rebuild and when
- **Type-Safe State Access**: Direct, type-safe access to bloc state
- **Built-in Error Handling**: Automatic error boundary protection
- **Streamlined Lifecycle**: Managed connection to bloc streams

## How It Works

A StatelessJuiceWidget:

1. Connects to its associated bloc's state stream
2. Listens for state changes
3. Rebuilds automatically when state changes (based on rebuild groups)
4. Handles cleanup automatically

## Basic Usage

Here's a simple example:

```dart
class CounterDisplay extends StatelessJuiceWidget<CounterBloc> {
  CounterDisplay({super.key, super.groups = const {"counter"}});

  @override
  Widget onBuild(BuildContext context, StreamStatus status) {
    return Text(
      'Count: ${bloc.state.count}',
      style: Theme.of(context).textTheme.headline4,
    );
  }
}
```

## Comparison with Regular StatelessWidget

Let's compare implementing the same counter display with both widgets:

### Regular StatelessWidget:
```dart
// Regular StatelessWidget
class CounterDisplay extends StatelessWidget {
  final CounterBloc bloc;  // Must be passed in
  final int count;        // Must be passed in
  
  CounterDisplay({
    required this.bloc,
    required this.count,
  });

  @override
  Widget build(BuildContext context) {
    // No automatic updates - parent must rebuild
    return Text('Count: $count');
  }
}

// Usage:
StreamBuilder<CounterState>(
  stream: bloc.stream,
  builder: (context, snapshot) {
    return CounterDisplay(
      bloc: bloc,
      count: snapshot.data?.count ?? 0,
    );
  },
)
```

### StatelessJuiceWidget:
```dart
// StatelessJuiceWidget
class CounterDisplay extends StatelessJuiceWidget<CounterBloc> {
  CounterDisplay({super.key, super.groups = const {"counter"}});

  @override
  Widget onBuild(BuildContext context, StreamStatus status) {
    // Automatic updates when state changes
    return Text('Count: ${bloc.state.count}');
  }
}

// Usage:
CounterDisplay()  // That's it!
```

Key Differences:
- **Automatic State Access**: No need to manually pass bloc or state
- **Built-in Reactivity**: No need for StreamBuilder or other wrappers
- **Smart Updates**: Control rebuilds through groups
- **Cleaner Code**: Less boilerplate, more focused on UI
- **Error Handling**: Automatic error boundaries

## Controlling Updates

One of the most powerful features of StatelessJuiceWidget is its ability to control exactly when it rebuilds:

```dart
class UserProfile extends StatelessJuiceWidget<ProfileBloc> {
  // Only rebuild when "profile" group is updated
  UserProfile({super.key, super.groups = const {"profile"}});

  @override
  Widget onBuild(BuildContext context, StreamStatus status) {
    return Column(
      children: [
        Text(bloc.state.name),
        Text(bloc.state.email),
      ],
    );
  }
}

class SaveButton extends StatelessJuiceWidget<ProfileBloc> {
  // Never rebuild - button state is static
  SaveButton({super.key, super.groups = optOutOfRebuilds});

  @override
  Widget onBuild(BuildContext context, StreamStatus status) {
    return ElevatedButton(
      onPressed: () => bloc.send(SaveProfileEvent()),
      child: Text('Save'),
    );
  }
}
```

## Handling Different States

StatelessJuiceWidget makes it easy to handle different UI states:

```dart
class UserProfile extends StatelessJuiceWidget<ProfileBloc> {
  UserProfile({super.key, super.groups = const {"profile"}});

  @override
  Widget onBuild(BuildContext context, StreamStatus status) {
    return status.when(
      updating: (state, _, __) => ProfileContent(profile: bloc.state.profile),
      waiting: (_, __, ___) => CircularProgressIndicator(),
      error: (_, __, ___) => Text('Error loading profile'),
      canceling: (_, __, ___) => Text('Operation cancelled'),
    );
  }
}
```

## Overridable Methods

StatelessJuiceWidget provides several methods you can override to customize its behavior:

### onInit()
Called when the widget is first initialized. Use this to perform any setup work.

```dart
class AnalyticsWidget extends StatelessJuiceWidget<AnalyticsBloc> {
  @override
  void onInit() {
    // Initialize analytics
    bloc.send(InitializeAnalyticsEvent());
  }

  @override
  Widget onBuild(BuildContext context, StreamStatus status) {
    return AnalyticsView(data: bloc.state.data);
  }
}
```

### onStateChange(StreamStatus status)
Called for each state change to determine if the widget should rebuild. Return false to prevent rebuild for this state change.

```dart
class OptimizedList extends StatelessJuiceWidget<ListBloc> {
  @override
  bool onStateChange(StreamStatus status) {
    // Only rebuild if items actually changed
    if (status is UpdatingStatus) {
      final oldItems = status.oldState.items;
      final newItems = status.state.items;
      return !ListEquality().equals(oldItems, newItems);
    }
    return true;
  }

  @override
  Widget onBuild(BuildContext context, StreamStatus status) {
    return ListView(
      children: bloc.state.items.map(
        (item) => ItemTile(item: item)
      ).toList(),
    );
  }
}
```

### onBuild(BuildContext context, StreamStatus status)
The main build method. Called whenever the widget needs to rebuild.

```dart
class UserProfile extends StatelessJuiceWidget<ProfileBloc> {
  @override
  Widget onBuild(BuildContext context, StreamStatus status) {
    return Column(
      children: [
        if (status is WaitingStatus)
          CircularProgressIndicator()
        else
          UserInfo(user: bloc.state.user),
          
        ErrorMessage(
          visible: status is FailureStatus,
          message: 'Failed to load profile'
        ),
      ],
    );
  }
}
```

### close(BuildContext context)
Called when the bloc stream is closed. Use this to show a final UI state or clean up.

```dart
class ConnectionWidget extends StatelessJuiceWidget<ConnectionBloc> {
  @override
  Widget close(BuildContext context) {
    // Show disconnected state when bloc closes
    return DisconnectedView(
      message: 'Connection closed',
      onReconnect: () => bloc.send(ReconnectEvent()),
    );
  }

  @override
  Widget onBuild(BuildContext context, StreamStatus status) {
    return ConnectionView(status: bloc.state.status);
  }
}
```

## Method Execution Order

Understanding when each method is called:

1. Widget Creation
   - Constructor called
   - onInit() called once

2. State Changes
   - onStateChange() called first
   - if returns true, onBuild() is called
   - if returns false, rebuild is skipped

3. Bloc Closure
   - close() called when bloc stream closes

Example showing all methods:

```dart
class CompleteExample extends StatelessJuiceWidget<ExampleBloc> {
  CompleteExample({super.key, super.groups = const {"example"}});

  @override
  void onInit() {
    // Called once when widget initializes
    bloc.send(InitializeEvent());
  }

  @override
  bool onStateChange(StreamStatus status) {
    // Called for every state change
    if (status is UpdatingStatus) {
      // Skip rebuild if only timestamp changed
      return status.state.data != status.oldState.data;
    }
    return true;
  }

  @override
  Widget onBuild(BuildContext context, StreamStatus status) {
    // Called when widget needs to rebuild
    return status.when(
      updating: (state, _, __) => DataView(data: bloc.state.data),
      waiting: (_, __, ___) => LoadingView(),
      error: (_, __, ___) => ErrorView(),
      canceling: (_, __, ___) => CanceledView(),
    );
  }

  @override
  Widget close(BuildContext context) {
    // Called when bloc stream closes
    return ClosedView(
      onReopen: () => bloc.send(ReopenEvent()),
    );
  }
}
```

## Best Practices

1. **Access State Through bloc.state**
   ```dart
   // ✅ Good: Clear state ownership
   Text(bloc.state.username)
   
   // ❌ Bad: Don't use status.state
   Text(status.state.username)
   ```

2. **Use Targeted Rebuild Groups**
   ```dart
   // ✅ Good: Only rebuilds profile section
   super.groups = const {"profile"}
   
   // ❌ Bad: Rebuilds on all changes
   super.groups = const {"*"}
   ```

3. **Separate UI Logic**
   ```dart
   // ✅ Good: Separate widgets by update needs
   class ProfileHeader extends StatelessJuiceWidget<ProfileBloc> {
     super.groups = const {"profile_header"}
   }
   
   class ProfileContent extends StatelessJuiceWidget<ProfileBloc> {
     super.groups = const {"profile_content"}
   }
   ```

4. **Handle All States**
   ```dart
   // ✅ Good: Handle all possible states
   status.when(
     updating: (state, _, __) => Content(),
     waiting: (_, __, ___) => Loading(),
     error: (_, __, ___) => ErrorView(),
     canceling: (_, __, ___) => CancelledView(),
   )
   ```

## Common Patterns

### Loading States
```dart
class DataView extends StatelessJuiceWidget<DataBloc> {
  @override
  Widget onBuild(BuildContext context, StreamStatus status) {
    if (status is WaitingStatus) {
      return Center(child: CircularProgressIndicator());
    }
    
    return ListView(
      children: bloc.state.items.map(
        (item) => ItemTile(item: item)
      ).toList(),
    );
  }
}
```

### Error Handling
```dart
class ErrorAwareWidget extends StatelessJuiceWidget<DataBloc> {
  @override
  Widget onBuild(BuildContext context, StreamStatus status) {
    if (status is FailureStatus) {
      return ErrorDisplay(
        message: 'Failed to load data',
        onRetry: () => bloc.send(RetryEvent()),
      );
    }
    
    return DataDisplay(data: bloc.state.data);
  }
}
```

### Static Components
```dart
class ActionButtons extends StatelessJuiceWidget<DataBloc> {
  // Opt out of rebuilds for static UI
  ActionButtons({super.key, super.groups = optOutOfRebuilds});

  @override
  Widget onBuild(BuildContext context, StreamStatus status) {
    return Row(
      children: [
        ElevatedButton(
          onPressed: () => bloc.send(SaveEvent()),
          child: Text('Save'),
        ),
        ElevatedButton(
          onPressed: () => bloc.send(CancelEvent()),
          child: Text('Cancel'),
        ),
      ],
    );
  }
}
```

## Summary

StatelessJuiceWidget provides a powerful, efficient way to build reactive UIs that:
- Automatically update in response to state changes
- Provide precise control over rebuilds
- Handle errors gracefully
- Reduce boilerplate code
- Maintain type safety

By using StatelessJuiceWidget, you get all the benefits of Juice's state management system with a clean, declarative API that makes building reactive UIs simpler and more maintainable.