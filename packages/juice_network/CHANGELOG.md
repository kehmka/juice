# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.7.1] - 2025-01-14

### Changed
- Refactored example app to use pure Juice patterns (StatelessJuiceWidget, dedicated blocs)
- Removed escape hatch patterns (JuiceAsyncBuilder, StatefulWidget with setState)

## [0.7.0] - 2025-01-13

### Initial Release

Feature-complete release with comprehensive network functionality for the Juice framework.

### Added
- **FetchBloc** - Unified BLoC for HTTP requests with Dio integration
- **Request Coalescing** - Automatic deduplication of concurrent identical requests
- **Intelligent Caching** - Multi-tier caching with configurable policies
  - Memory cache for fast access
  - Disk cache via juice_storage for persistence
  - Five cache policies: networkFirst, cacheFirst, staleWhileRevalidate, cacheOnly, networkOnly
- **Automatic Retry** - Configurable retry with exponential backoff
- **Request Tracking** - Real-time visibility into inflight requests
- **Statistics** - Built-in metrics for cache hits, success rates, response times
- **Interceptors** - Extensible interceptor system with priority ordering
  - AuthInterceptor for bearer token authentication
  - LoggingInterceptor for request/response logging
  - RetryInterceptor for custom retry logic
  - ETagInterceptor for conditional requests
  - RefreshTokenInterceptor for automatic token refresh
- **ReconfigureInterceptorsEvent** - Runtime interceptor reconfiguration
- **HTTP Methods** - Full support for GET, POST, PUT, PATCH, DELETE
- **Error Handling** - Typed FetchError hierarchy for precise error handling
- **Rebuild Groups** - Targeted widget rebuilds per request/cache/stats

### Documentation
- Comprehensive README with badges and examples
- Complete documentation in `doc/` folder:
  - Getting Started guide
  - Caching guide
  - Coalescing guide
  - Interceptors reference
  - Errors reference

### Dependencies
- Requires `juice: ^1.2.0`
- Requires `juice_storage: ^0.9.0`
- Uses `dio: ^5.4.0` for HTTP
