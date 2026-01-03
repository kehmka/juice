import 'package:juice/juice.dart';

/// Event to initiate login
class LoginEvent extends EventBase {
  final String email;
  final String password;

  LoginEvent({required this.email, required this.password});
}

/// Event emitted after successful login
/// This is the event other blocs can subscribe to
class LoginSuccessEvent extends EventBase {
  final String userId;
  final String email;

  LoginSuccessEvent({required this.userId, required this.email});

  @override
  Set<String>? get groupsToRebuild => {'auth'};
}

/// Event to initiate logout
class LogoutEvent extends EventBase {}

/// Event emitted after logout
/// This is the event other blocs can subscribe to
class LogoutSuccessEvent extends EventBase {
  @override
  Set<String>? get groupsToRebuild => {'auth'};
}
