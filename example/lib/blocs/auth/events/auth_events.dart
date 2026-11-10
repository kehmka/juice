import 'package:juice/juice.dart';

/// Event to initiate login
class LoginEvent extends EventBase {
  final String email;
  final String password;

  LoginEvent({required this.email, required this.password});
}

/// Event to initiate logout
class LogoutEvent extends EventBase {}
