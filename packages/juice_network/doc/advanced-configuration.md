---
layout: default
title: Advanced Configuration
nav_order: 6
---

# Advanced Configuration

This guide covers advanced configuration options including platform-specific settings, custom Dio instances, and security configurations.

## Custom Dio Instance

You can provide your own pre-configured Dio instance for full control:

```dart
// Create custom Dio with specific settings
final customDio = Dio(BaseOptions(
  baseUrl: 'https://api.example.com',
  connectTimeout: const Duration(seconds: 10),
  receiveTimeout: const Duration(seconds: 10),
  headers: {'Custom-Header': 'value'},
));

// Add custom Dio interceptors if needed
customDio.interceptors.add(MyCustomDioInterceptor());

// Pass to FetchBloc
final fetchBloc = FetchBloc(
  storageBloc: storageBloc,
  dio: customDio,  // Your custom instance
);
```

**Note:** When providing a custom Dio instance, FetchBloc will still apply `FetchConfig` settings during initialization. The custom Dio serves as the base instance.

---

## Platform Configuration

`PlatformConfig` provides platform-specific options that are safely ignored on unsupported platforms.

### Certificate Pinning (Mobile/Desktop)

Protect against man-in-the-middle attacks by pinning certificates:

```dart
final platformConfig = PlatformConfig(
  certificatePinning: CertificatePinConfig(
    host: 'api.example.com',
    sha256Fingerprints: [
      'SHA256/AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=',
      'SHA256/BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB=',
    ],
  ),
);
```

Certificate pinning is **ignored on web** (the browser manages TLS).

### HTTP Proxy (Mobile/Desktop)

Route traffic through a proxy server:

```dart
final platformConfig = PlatformConfig(
  proxy: ProxyConfig(
    host: 'proxy.company.com',
    port: 8080,
    username: 'user',      // optional
    password: 'password',  // optional
  ),
);
```

Useful for:
- Corporate network requirements
- Debugging with tools like Charles Proxy or mitmproxy
- Network monitoring

### Custom HTTP Adapter (Mobile/Desktop)

Use a custom HTTP client adapter (e.g., for HTTP/2):

```dart
import 'package:dio_http2_adapter/dio_http2_adapter.dart';

final platformConfig = PlatformConfig(
  httpAdapter: Http2Adapter(
    ConnectionManager(
      idleTimeout: Duration(seconds: 15),
    ),
  ),
);
```

### CORS Credentials (Web Only)

Include cookies in cross-origin requests:

```dart
final platformConfig = PlatformConfig(
  withCredentials: true,  // Send cookies with CORS requests
);
```

This is **ignored on mobile/desktop** where cookies are always sent.

---

## Concurrency Limiting

Control how many requests execute simultaneously:

```dart
FetchConfig(
  maxConcurrentRequests: 6,  // Default is 10
);
```

Requests beyond this limit are queued and execute as slots become available. This prevents:
- Overwhelming the server
- Exhausting device resources
- Hitting rate limits

---

## Authentication Identity Provider

When using authentication interceptors, provide an identity for cache/coalescing isolation:

```dart
FetchBloc(
  storageBloc: storageBloc,
  authIdentityProvider: () => authBloc.state.userId,
)
```

This ensures:
- Each user has isolated cache entries
- Requests don't coalesce across different users
- No data leaks between authenticated sessions

**Important:** This is **required** when using `AuthInterceptor`. Without it, one user could receive another user's cached responses.

---

## Status Code Validation

Control how HTTP status codes are handled:

```dart
FetchConfig(
  validateStatus: true,   // Throw HttpError on 4xx/5xx (default)
  // or
  validateStatus: false,  // Never throw, always return response
);
```

With `validateStatus: false`, you handle all status codes in your decode function:

```dart
fetchBloc.send(GetEvent(
  url: '/posts',
  decode: (json) {
    // Handle all responses, including errors
    if (json['error'] != null) {
      throw Exception(json['error']);
    }
    return Post.fromJson(json);
  },
));
```

---

## Complete Configuration Example

```dart
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Storage setup
  BlocScope.register<StorageBloc>(
    () => StorageBloc(config: const StorageConfig(
      hiveBoxesToOpen: [CacheManager.cacheBoxName],
    )),
    lifecycle: BlocLifecycle.permanent,
  );

  final storageBloc = BlocScope.get<StorageBloc>();
  await storageBloc.initialize();

  // FetchBloc with auth identity
  BlocScope.register<FetchBloc>(
    () => FetchBloc(
      storageBloc: storageBloc,
      authIdentityProvider: () => authBloc.state.userId,
    ),
    lifecycle: BlocLifecycle.permanent,
  );

  final fetchBloc = BlocScope.get<FetchBloc>();

  // Initialize with full configuration
  await fetchBloc.send(InitializeFetchEvent(
    config: FetchConfig(
      baseUrl: 'https://api.example.com',
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 30),
      sendTimeout: const Duration(seconds: 15),
      defaultCachePolicy: CachePolicy.networkFirst,
      defaultTtl: const Duration(minutes: 5),
      maxCacheSize: 100 * 1024 * 1024,  // 100 MB
      maxConcurrentRequests: 6,
      defaultHeaders: {
        'Accept': 'application/json',
        'X-App-Version': '1.0.0',
      },
      followRedirects: true,
      maxRedirects: 5,
      defaultMaxRetries: 3,
      validateStatus: true,
    ),
    interceptors: [
      TimingInterceptor(),
      LoggingInterceptor(logger: print, logBody: kDebugMode),
      AuthInterceptor(
        tokenProvider: () async => authBloc.state.accessToken,
        skipAuth: (path) => path.startsWith('/public'),
      ),
      RetryInterceptor(maxRetries: 3),
    ],
  ));

  runApp(MyApp());
}
```

---

## Environment-Based Configuration

Different configurations for development vs production:

```dart
FetchConfig getConfig(Environment env) {
  switch (env) {
    case Environment.development:
      return FetchConfig(
        baseUrl: 'https://dev-api.example.com',
        connectTimeout: const Duration(seconds: 60),  // Longer for debugging
        defaultMaxRetries: 1,  // Fail fast
      );
    case Environment.staging:
      return FetchConfig(
        baseUrl: 'https://staging-api.example.com',
        defaultMaxRetries: 2,
      );
    case Environment.production:
      return FetchConfig(
        baseUrl: 'https://api.example.com',
        connectTimeout: const Duration(seconds: 15),
        defaultMaxRetries: 3,
      );
  }
}

List<FetchInterceptor> getInterceptors(Environment env) {
  return [
    TimingInterceptor(),
    if (env == Environment.development)
      LoggingInterceptor(
        logger: print,
        logBody: true,
        logHeaders: true,
      ),
    AuthInterceptor(tokenProvider: () async => token),
    RetryInterceptor(maxRetries: env == Environment.production ? 3 : 1),
  ];
}
```
