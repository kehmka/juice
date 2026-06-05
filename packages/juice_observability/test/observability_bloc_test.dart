import 'package:flutter_test/flutter_test.dart';
import 'package:juice_observability/juice_observability.dart';

class RecordingReporter implements CrashReporter {
  final List<Object> errors = [];
  final List<Breadcrumb> crumbs = [];
  final List<List<Breadcrumb>> errorBreadcrumbs = [];
  String? user;
  bool disposed = false;
  final bool throwOnRecord;
  RecordingReporter({this.throwOnRecord = false});

  @override
  Future<void> recordError(Object error, StackTrace? stack,
      {bool fatal = false, List<Breadcrumb> breadcrumbs = const []}) async {
    if (throwOnRecord) throw StateError('bad reporter');
    errors.add(error);
    errorBreadcrumbs.add(breadcrumbs);
  }

  @override
  Future<void> addBreadcrumb(Breadcrumb crumb) async => crumbs.add(crumb);
  @override
  Future<void> setUser(String? userId) async => user = userId;
  @override
  Future<void> setContext(String key, Object? value) async {}
  @override
  Future<void> dispose() async => disposed = true;
}

void main() {
  Future<void> settle([int ms = 20]) =>
      Future<void>.delayed(Duration(milliseconds: ms));

  // Don't install global handlers in unit tests.
  ObservabilityBloc build(List<CrashReporter> reporters,
          {int maxBreadcrumbs = 50}) =>
      ObservabilityBloc.withConfig(ObservabilityConfig(
        reporters: reporters,
        captureUncaught: false,
        maxBreadcrumbs: maxBreadcrumbs,
      ));

  group('ObservabilityState model', () {
    test('defaults', () {
      const s = ObservabilityState();
      expect(s.enabled, isTrue);
      expect(s.errorCount, 0);
      expect(s.breadcrumbs, isEmpty);
    });
  });

  group('Recording', () {
    test('recordError fans out to all reporters with breadcrumbs', () async {
      final a = RecordingReporter();
      final b = RecordingReporter();
      final bloc = build([a, b]);
      await settle();

      bloc.breadcrumb('opened screen', category: 'nav');
      await settle();

      bloc.recordError(StateError('kaboom'), StackTrace.current);
      await settle();

      expect(a.errors.length, 1);
      expect(b.errors.length, 1);
      expect(a.errorBreadcrumbs.single.single.message, 'opened screen');
      expect(bloc.state.errorCount, 1);
      expect(bloc.state.lastError, contains('kaboom'));
      await bloc.close();
    });

    test('a throwing reporter does not break the others', () async {
      final bad = RecordingReporter(throwOnRecord: true);
      final good = RecordingReporter();
      final bloc = build([bad, good]);
      await settle();

      bloc.recordError(StateError('x'));
      await settle();
      expect(good.errors.length, 1);
      expect(bloc.state.errorCount, 1);
      await bloc.close();
    });

    test('disabled capture drops errors', () async {
      final a = RecordingReporter();
      final bloc = build([a]);
      await settle();

      bloc.setEnabled(false);
      await settle();
      bloc.recordError(StateError('x'));
      await settle();

      expect(a.errors, isEmpty);
      expect(bloc.state.errorCount, 0);
      await bloc.close();
    });
  });

  group('Breadcrumbs', () {
    test('ring is trimmed to maxBreadcrumbs', () async {
      final a = RecordingReporter();
      final bloc = build([a], maxBreadcrumbs: 3);
      await settle();

      for (var i = 0; i < 5; i++) {
        bloc.breadcrumb('crumb $i');
      }
      await settle();

      expect(bloc.state.breadcrumbs.length, 3);
      expect(bloc.state.breadcrumbs.map((c) => c.message),
          ['crumb 2', 'crumb 3', 'crumb 4']);
      await bloc.close();
    });
  });

  group('Identity & lifecycle', () {
    test('setUser reaches reporters and state', () async {
      final a = RecordingReporter();
      final bloc = build([a]);
      await settle();

      bloc.setUser('u1');
      await settle();
      expect(a.user, 'u1');
      expect(bloc.state.userId, 'u1');
      await bloc.close();
    });

    test('close disposes reporters', () async {
      final a = RecordingReporter();
      final bloc = build([a]);
      await settle();
      await bloc.close();
      expect(a.disposed, isTrue);
    });
  });
}
