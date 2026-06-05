/// A logged breadcrumb — context leading up to an error.
class Breadcrumb {
  final String message;
  final String? category;
  final Map<String, Object?> data;

  const Breadcrumb(this.message, {this.category, this.data = const {}});

  @override
  String toString() =>
      'Breadcrumb(${category == null ? '' : '$category: '}$message)';
}

/// A destination for crash reports + breadcrumbs — a vendor adapter (Sentry,
/// Crashlytics, …). The bloc fans out to one or more; it never depends on a
/// vendor SDK.
abstract class CrashReporter {
  /// Record an error (optionally fatal) with its stack and the recent breadcrumbs.
  Future<void> recordError(
    Object error,
    StackTrace? stack, {
    bool fatal,
    List<Breadcrumb> breadcrumbs,
  });

  /// Add a breadcrumb to the vendor's trail.
  Future<void> addBreadcrumb(Breadcrumb crumb);

  /// Associate (or clear) the current user.
  Future<void> setUser(String? userId);

  /// Set a custom context key/value.
  Future<void> setContext(String key, Object? value);

  /// Release resources.
  Future<void> dispose();
}

/// Prints to the console — handy in development and tests.
class ConsoleCrashReporter implements CrashReporter {
  final void Function(String) _out;
  ConsoleCrashReporter([void Function(String)? out]) : _out = out ?? print;

  @override
  Future<void> recordError(Object error, StackTrace? stack,
      {bool fatal = false, List<Breadcrumb> breadcrumbs = const []}) async {
    _out('[crash${fatal ? ':fatal' : ''}] $error');
  }

  @override
  Future<void> addBreadcrumb(Breadcrumb crumb) async => _out('[crumb] $crumb');
  @override
  Future<void> setUser(String? userId) async => _out('[crash] user: $userId');
  @override
  Future<void> setContext(String key, Object? value) async =>
      _out('[crash] ctx $key=$value');
  @override
  Future<void> dispose() async {}
}

/// Discards everything — a safe default when no reporter is wired.
class NoopCrashReporter implements CrashReporter {
  const NoopCrashReporter();
  @override
  Future<void> recordError(Object error, StackTrace? stack,
      {bool fatal = false, List<Breadcrumb> breadcrumbs = const []}) async {}
  @override
  Future<void> addBreadcrumb(Breadcrumb crumb) async {}
  @override
  Future<void> setUser(String? userId) async {}
  @override
  Future<void> setContext(String key, Object? value) async {}
  @override
  Future<void> dispose() async {}
}
