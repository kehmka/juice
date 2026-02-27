/// Authentication lifecycle management for Juice applications.
///
/// juice_auth provides a foundation bloc for authentication state, token
/// management, and session lifecycle. It decouples auth logic from any
/// specific provider (Firebase, Supabase, custom API) via the [AuthProvider]
/// interface.
///
/// ## Quick Start
///
/// ```dart
/// // 1. Register
/// BlocScope.register<AuthBloc>(
///   () => AuthBloc(config: AuthConfig(
///     providers: {'email': MyAuthProvider()},
///   )),
///   lifecycle: BlocLifecycle.permanent,
/// );
///
/// // 2. Login
/// BlocScope.get<AuthBloc>().loginWithEmail('user@example.com', 'pass');
///
/// // 3. React
/// class AuthGate extends StatelessJuiceWidget<AuthBloc> {
///   AuthGate({super.key}) : super(groups: {AuthGroups.status});
///   @override
///   Widget onBuild(BuildContext context, StreamStatus status) {
///     return bloc.state.isAuthenticated ? HomeScreen() : LoginScreen();
///   }
/// }
/// ```
///
/// ## Rebuild Groups
///
/// - `auth:status` — login, logout, session expiry
/// - `auth:user` — user profile changes
/// - `auth:session` — token refresh, session update
/// - `auth:error` — auth error occurred
library juice_auth;

// Provider interface
export 'src/auth_provider.dart';
export 'src/auth_credentials.dart';
export 'src/auth_result.dart';

// State and models
export 'src/auth_state.dart';
export 'src/auth_user.dart';
export 'src/auth_session.dart';

// Configuration
export 'src/auth_config.dart';

// Events
export 'src/auth_events.dart';

// Errors
export 'src/auth_errors.dart';

// Bloc
export 'src/auth_bloc.dart';
