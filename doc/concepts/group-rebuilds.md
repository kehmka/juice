# Smart Widget Rebuilding in Juice

Juice provides a powerful group-based system for controlling exactly which widgets rebuild in response to state changes. This system helps optimize performance by preventing unnecessary rebuilds while keeping code clean and maintainable.

## Core Concepts

### Rebuild Groups

Every Juice widget can specify which groups it belongs to:

```dart
class ProfileHeader extends StatelessJuiceWidget<ProfileBloc> {
  // Widget rebuilds when "profile_header" group is triggered
  ProfileHeader({super.key, super.groups = const {"profile_header"}});
  
  @override
  Widget onBuild(BuildContext context, StreamStatus status) {
    return Text(bloc.state.userName);
  }
}
```

### Special Group Values

```dart
// Always rebuild (default)
const Set<String> rebuildAlways = {"*"};

// Never rebuild
const Set<String> optOutOfRebuilds = {"-"};
```

## Configuring Widgets

### Single Group
```dart
// Basic group membership
class UserAvatar extends StatelessJuiceWidget<UserBloc> {
  UserAvatar({super.key, super.groups = const {"avatar"}});
}
```

### Multiple Groups
```dart
// Widget participates in multiple groups
class UserStats extends StatelessJuiceWidget<UserBloc> {
  UserStats({
    super.key, 
    super.groups = const {"stats", "achievements"}
  });
}
```

### Opting Out
```dart
// Widget never rebuilds from state changes
class StaticHeader extends StatelessJuiceWidget<AppBloc> {
  StaticHeader({super.key, super.groups = optOutOfRebuilds});
}
```

### Always Rebuild
```dart
// Widget rebuilds on all state changes
class DebugPanel extends StatelessJuiceWidget<AppBloc> {
  DebugPanel({super.key, super.groups = rebuildAlways});
}
```

## Emitting Updates

### Basic Emit
```dart
class UpdateProfileUseCase extends BlocUseCase<ProfileBloc, UpdateProfileEvent> {
  @override
  Future<void> execute(UpdateProfileEvent event) async {
    // Only profile-related widgets rebuild
    emitUpdate(
      newState: bloc.state.copyWith(name: event.name),
      groupsToRebuild: {"profile_header", "profile_details"}
    );
  }
}
```

### Multiple Groups
```dart
class CompleteAchievementUseCase extends BlocUseCase<UserBloc, AchievementEvent> {
  @override
  Future<void> execute(AchievementEvent event) async {
    // Update both achievement and stats widgets
    emitUpdate(
      newState: bloc.state.withNewAchievement(event.achievement),
      groupsToRebuild: {"achievements", "stats", "profile_header"}
    );
  }
}
```

### Status-Specific Rebuilds
```dart
class LoadProfileUseCase extends BlocUseCase<ProfileBloc, LoadProfileEvent> {
  @override
  Future<void> execute(LoadProfileEvent event) async {
    // Show loading in header only
    emitWaiting(groupsToRebuild: {"profile_header"});
    
    try {
      final profile = await profileService.load();
      
      // Update all profile widgets
      emitUpdate(
        newState: bloc.state.copyWith(profile: profile),
        groupsToRebuild: {
          "profile_header", 
          "profile_details",
          "profile_stats"
        }
      );
    } catch (e) {
      // Show error in header only
      emitFailure(groupsToRebuild: {"profile_header"});
    }
  }
}
```

## Real-World Examples

### Chat Interface
```dart
// Message list only updates for new messages
class MessageList extends StatelessJuiceWidget<ChatBloc> {
  MessageList({super.key, super.groups = const {"messages"}});
  
  @override
  Widget onBuild(BuildContext context, StreamStatus status) {
    return ListView(
      children: bloc.state.messages.map(buildMessage).toList(),
    );
  }
}

// Status updates independently
class ChatStatus extends StatelessJuiceWidget<ChatBloc> {
  ChatStatus({super.key, super.groups = const {"chat_status"}});
  
  @override
  Widget onBuild(BuildContext context, StreamStatus status) {
    return Text(bloc.state.statusText);
  }
}

// Send message use case coordinates updates
class SendMessageUseCase extends BlocUseCase<ChatBloc, SendMessageEvent> {
  @override
  Future<void> execute(SendMessageEvent event) async {
    // Update just the status
    emitWaiting(groupsToRebuild: {"chat_status"});
    
    try {
      await chatService.send(event.message);
      
      // Update both messages and status
      emitUpdate(
        newState: bloc.state.withNewMessage(event.message),
        groupsToRebuild: {"messages", "chat_status"}
      );
    } catch (e) {
      // Show error only in status
      emitFailure(groupsToRebuild: {"chat_status"});
    }
  }
}
```

### Form With Validation
```dart
// Form fields update independently
class EmailField extends StatelessJuiceWidget<FormBloc> {
  EmailField({super.key, super.groups = const {"email_field"}});
}

class PasswordField extends StatelessJuiceWidget<FormBloc> {
  PasswordField({super.key, super.groups = const {"password_field"}});
}

// Submit button depends on all fields
class SubmitButton extends StatelessJuiceWidget<FormBloc> {
  SubmitButton({
    super.key, 
    super.groups = const {"email_field", "password_field"}
  });
}

// Validation use case updates specific fields
class ValidateEmailUseCase extends BlocUseCase<FormBloc, ValidateEmailEvent> {
  @override
  Future<void> execute(ValidateEmailEvent event) async {
    emitWaiting(groupsToRebuild: {"email_field"});
    
    try {
      final isValid = await validateEmail(event.email);
      emitUpdate(
        newState: bloc.state.copyWith(
          email: event.email,
          isEmailValid: isValid
        ),
        groupsToRebuild: {"email_field"}
      );
    } catch (e) {
      emitFailure(groupsToRebuild: {"email_field"});
    }
  }
}
```

## Best Practices

### Group Naming
```dart
// ✅ Good: Clear, specific group names
const groups = {
  "profile_header",
  "profile_details",
  "achievement_list"
};

// ❌ Bad: Vague, ambiguous names
const groups = {
  "header",  // Too generic
  "data",    // Too vague
  "list"     // Not specific enough
};
```

### Group Organization
```dart
// Define groups as constants
abstract class ProfileGroups {
  static const header = "profile_header";
  static const details = "profile_details";
  static const stats = "profile_stats";
  
  // Related groups
  static const all = {header, details, stats};
  static const summary = {header, stats};
}

// Use in widgets
class ProfileHeader extends StatelessJuiceWidget<ProfileBloc> {
  ProfileHeader({
    super.key, 
    super.groups = const {ProfileGroups.header}
  });
}

// Use in use cases
class UpdateProfileUseCase extends BlocUseCase<ProfileBloc, UpdateEvent> {
  @override
  Future<void> execute(UpdateEvent event) async {
    emitUpdate(
      newState: bloc.state.copyWith(profile: event.profile),
      groupsToRebuild: ProfileGroups.all
    );
  }
}
```

### Performance Optimization
```dart
// Only update what's necessary
class UpdateAvatarUseCase extends BlocUseCase<ProfileBloc, UpdateAvatarEvent> {
  @override
  Future<void> execute(UpdateAvatarEvent event) async {
    // Don't rebuild entire profile, just avatar-related widgets
    emitUpdate(
      newState: bloc.state.copyWith(avatar: event.avatar),
      groupsToRebuild: {"avatar", "header_avatar"}
    );
  }
}

// Use optOutOfRebuilds for static content
class ProfileLayout extends StatelessJuiceWidget<ProfileBloc> {
  ProfileLayout({super.key, super.groups = optOutOfRebuilds});
  
  @override
  Widget onBuild(BuildContext context, StreamStatus status) {
    return Column(
      children: [
        ProfileHeader(),  // Rebuilds with "header" group
        ProfileContent(), // Rebuilds with "content" group
        const StaticFooter(), // Never rebuilds
      ],
    );
  }
}
```

### Testing
```dart
void main() {
  test('use case updates correct groups', () async {
    final useCase = UpdateProfileUseCase();
    final event = UpdateProfileEvent(name: 'Test');
    
    // Mock emit methods to capture rebuilds
    var capturedGroups = <String>{};
    useCase.emitUpdate = ({
      required Set<String> groupsToRebuild,
      required BlocState newState
    }) {
      capturedGroups = groupsToRebuild;
    };
    
    await useCase.execute(event);
    
    expect(
      capturedGroups, 
      equals({"profile_header", "profile_details"})
    );
  });
}
```

## Common Patterns

### Loading States
```dart
class LoadDataUseCase extends BlocUseCase<DataBloc, LoadDataEvent> {
  @override
  Future<void> execute(LoadDataEvent event) async {
    // Show loading spinner only in content area
    emitWaiting(groupsToRebuild: {"content"});
    
    try {
      final data = await fetchData();
      
      // Update content and summary
      emitUpdate(
        newState: bloc.state.copyWith(data: data),
        groupsToRebuild: {"content", "summary"}
      );
    } catch (e) {
      // Show error only in content area
      emitFailure(groupsToRebuild: {"content"});
    }
  }
}
```

### Progressive Updates
```dart
class ProcessOrderUseCase extends BlocUseCase<OrderBloc, ProcessOrderEvent> {
  @override
  Future<void> execute(ProcessOrderEvent event) async {
    // Update status
    emitUpdate(
      newState: bloc.state.copyWith(status: 'Validating'),
      groupsToRebuild: {"order_status"}
    );
    
    // Process steps
    await validateOrder();
    emitUpdate(
      newState: bloc.state.copyWith(status: 'Processing Payment'),
      groupsToRebuild: {"order_status"}
    );
    
    await processPayment();
    emitUpdate(
      newState: bloc.state.copyWith(
        status: 'Complete',
        isProcessed: true
      ),
      groupsToRebuild: {"order_status", "order_summary"}
    );
  }
}
```

Remember: The group-based rebuild system is one of Juice's most powerful features for performance optimization. Use it thoughtfully to create responsive, efficient UIs.