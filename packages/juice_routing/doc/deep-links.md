---
layout: default
title: Deep Linking
nav_order: 5
---

# Deep Linking

juice_routing provides unified deep link handling for web URLs, mobile deep links, and in-app navigation through Navigator 2.0 integration.

## How Deep Links Work

Deep links flow through the same path resolution and guard pipeline as regular navigation:

1. URL arrives (browser, app link, etc.)
2. `JuiceRouteInformationParser` parses the URL
3. `JuiceRouterDelegate` receives the path
4. `NavigateEvent` is sent to `RoutingBloc`
5. Guards run, navigation commits (or redirects/blocks)

This means:
- **Same guards apply** - Auth guards protect deep links too
- **Same path resolution** - Parameters extracted consistently
- **Same error handling** - Invalid paths go to not-found route

## Setup for Web

Navigator 2.0 integration handles web URLs automatically:

```dart
class MyApp extends StatelessWidget {
  final RoutingBloc routingBloc;

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      routerDelegate: JuiceRouterDelegate(routingBloc: routingBloc),
      routeInformationParser: const JuiceRouteInformationParser(),
    );
  }
}
```

Now URLs like `https://myapp.com/profile/123` work:
- Browser URL bar updates as you navigate
- Back/forward buttons work
- Direct URL entry works
- Bookmarks work

## Setup for Mobile

### Android

Add intent filters in `android/app/src/main/AndroidManifest.xml`:

```xml
<activity android:name=".MainActivity">
    <!-- Deep Links -->
    <intent-filter>
        <action android:name="android.intent.action.VIEW" />
        <category android:name="android.intent.category.DEFAULT" />
        <category android:name="android.intent.category.BROWSABLE" />
        <data android:scheme="myapp" />
    </intent-filter>

    <!-- App Links (verified) -->
    <intent-filter android:autoVerify="true">
        <action android:name="android.intent.action.VIEW" />
        <category android:name="android.intent.category.DEFAULT" />
        <category android:name="android.intent.category.BROWSABLE" />
        <data
            android:scheme="https"
            android:host="myapp.com" />
    </intent-filter>
</activity>
```

### iOS

Add URL schemes in `ios/Runner/Info.plist`:

```xml
<key>CFBundleURLTypes</key>
<array>
    <dict>
        <key>CFBundleURLSchemes</key>
        <array>
            <string>myapp</string>
        </array>
    </dict>
</array>
```

For Universal Links, add associated domains in Xcode:
- `applinks:myapp.com`

## Cold Start vs Warm Start

### Cold Start

App is not running, deep link launches it:

1. App starts
2. `RoutingBloc` initializes with `initialPath: '/'`
3. Navigator 2.0 receives the deep link URL
4. `setNewRoutePath` triggers navigation to the deep link path
5. Guards run, user lands on the deep linked page (or is redirected)

### Warm Start

App is running in background:

1. Deep link arrives
2. Navigator 2.0 receives the URL
3. `setNewRoutePath` triggers navigation
4. Guards run, navigation commits

Both cases go through the same guard pipeline.

## Handling Protected Deep Links

Deep links to protected routes work with guards:

```dart
// User taps: myapp://profile/123
// But they're not logged in

RouteConfig(
  path: '/profile/:userId',
  builder: (ctx) => ProfileScreen(userId: ctx.params['userId']!),
  guards: [AuthGuard()],  // Will redirect to /login
)

class AuthGuard extends RouteGuard {
  @override
  Future<GuardResult> check(RouteContext context) async {
    if (!isLoggedIn) {
      // Redirect to login, preserving the intended destination
      return GuardResult.redirect(
        '/login',
        returnTo: context.targetPath,  // '/profile/123'
      );
    }
    return const GuardResult.allow();
  }
}
```

After login, use the `returnTo` to complete the deep link:

```dart
// In LoginScreen after successful login:
void onLoginSuccess() {
  final returnTo = routingBloc.state.current?.query['returnTo'];
  if (returnTo != null) {
    routingBloc.navigate(returnTo);
  } else {
    routingBloc.navigate('/');
  }
}
```

## Query Parameters

Query parameters are preserved through deep links:

```dart
// Deep link: myapp://search?q=flutter&category=packages

RouteConfig(
  path: '/search',
  builder: (ctx) => SearchScreen(
    query: ctx.query['q'],           // 'flutter'
    category: ctx.query['category'], // 'packages'
  ),
)
```

## Path Parameters

Path parameters work the same as in-app navigation:

```dart
// Deep link: myapp://users/42/posts/101

RouteConfig(
  path: '/users/:userId/posts/:postId',
  builder: (ctx) => PostScreen(
    userId: ctx.params['userId']!,   // '42'
    postId: ctx.params['postId']!,   // '101'
  ),
)
```

## Not Found Handling

Invalid deep links go to your not-found route:

```dart
// Deep link: myapp://this-does-not-exist

final appRoutes = RoutingConfig(
  routes: [...],
  notFoundRoute: RouteConfig(
    path: '/404',
    builder: (ctx) => NotFoundScreen(
      requestedPath: ctx.entry.path,  // '/this-does-not-exist'
    ),
  ),
);
```

## Testing Deep Links

### Manual Testing

```bash
# Android
adb shell am start -a android.intent.action.VIEW \
  -d "myapp://profile/123" com.example.myapp

# iOS Simulator
xcrun simctl openurl booted "myapp://profile/123"
```

### Unit Testing

```dart
test('deep link to protected route redirects to login', () async {
  // Setup: user not logged in
  final authBloc = MockAuthBloc();
  when(authBloc.state).thenReturn(AuthState(isLoggedIn: false));

  final routingBloc = RoutingBloc();
  routingBloc.send(InitializeRoutingEvent(config: appRoutes));

  // Simulate deep link
  routingBloc.navigate('/profile/123');

  // Should redirect to login with returnTo
  await Future.delayed(Duration.zero);
  expect(routingBloc.state.currentPath, '/login');
  expect(routingBloc.state.current?.query['returnTo'], '/profile/123');
});
```

## Best Practices

### 1. Always Handle Authentication

Protected routes should redirect, not block:

```dart
// Good: User can complete the flow
return GuardResult.redirect('/login', returnTo: context.targetPath);

// Avoid: User sees error, loses context
return GuardResult.block('Not authenticated');
```

### 2. Validate Path Parameters

Deep links can contain arbitrary data:

```dart
RouteConfig(
  path: '/users/:userId',
  builder: (ctx) {
    final userId = ctx.params['userId']!;
    // Validate before using
    if (int.tryParse(userId) == null) {
      return const InvalidUserScreen();
    }
    return UserScreen(userId: userId);
  },
)
```

### 3. Provide Fallbacks

Not all deep links will resolve:

```dart
notFoundRoute: RouteConfig(
  path: '/404',
  builder: (ctx) => NotFoundScreen(
    message: 'The page you\'re looking for doesn\'t exist.',
    showHomeButton: true,
  ),
)
```

### 4. Test Both Cold and Warm Start

Deep links behave differently depending on app state. Test both scenarios.

### 5. Log Deep Link Usage

Track which deep links users are using:

```dart
class DeepLinkLoggingGuard extends RouteGuard {
  @override
  int get priority => 1;

  @override
  Future<GuardResult> check(RouteContext context) async {
    analytics.logDeepLink(context.targetPath);
    return const GuardResult.allow();
  }
}
```
