import 'package:juice/juice.dart';

/// Event to load user profile
class LoadProfileEvent extends EventBase {
  final String userId;
  final String email;

  LoadProfileEvent({required this.userId, required this.email});

  @override
  Set<String>? get groupsToRebuild => {'profile'};
}

/// Event to clear profile (on logout)
class ClearProfileEvent extends EventBase {
  @override
  Set<String>? get groupsToRebuild => {'profile'};
}
