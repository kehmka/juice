import 'package:flutter_test/flutter_test.dart';
import 'package:juice_analytics/juice_analytics.dart';

class RecordingSink implements AnalyticsSink {
  final List<String> events = [];
  final List<String> screens = [];
  String? user;
  bool flushed = false;
  bool disposed = false;
  final bool throwOnEvent;
  RecordingSink({this.throwOnEvent = false});

  @override
  Future<void> logEvent(String name, Map<String, Object?> params) async {
    if (throwOnEvent) throw StateError('bad sink');
    events.add(name);
  }

  @override
  Future<void> setScreen(String name) async => screens.add(name);
  @override
  Future<void> setUser(String? userId, Map<String, Object?> traits) async =>
      user = userId;
  @override
  Future<void> flush() async => flushed = true;
  @override
  Future<void> dispose() async => disposed = true;
}

void main() {
  Future<void> settle([int ms = 20]) =>
      Future<void>.delayed(Duration(milliseconds: ms));

  group('AnalyticsState model', () {
    test('defaults', () {
      const s = AnalyticsState();
      expect(s.enabled, isTrue);
      expect(s.eventCount, 0);
      expect(s.droppedCount, 0);
    });
  });

  group('Tracking', () {
    test('logs fan out to all sinks; count increments', () async {
      final a = RecordingSink();
      final b = RecordingSink();
      final bloc = AnalyticsBloc.withConfig(AnalyticsConfig(sinks: [a, b]));
      await settle();

      bloc.log('checkout', {'cart': 3});
      await settle();

      expect(a.events, ['checkout']);
      expect(b.events, ['checkout']);
      expect(bloc.state.eventCount, 1);
      await bloc.close();
    });

    test('screen + user fan out', () async {
      final a = RecordingSink();
      final bloc = AnalyticsBloc.withConfig(AnalyticsConfig(sinks: [a]));
      await settle();

      bloc.screen('Cart');
      bloc.setUser('u1', {'plan': 'pro'});
      await settle();

      expect(a.screens, ['Cart']);
      expect(a.user, 'u1');
      expect(bloc.state.screenName, 'Cart');
      expect(bloc.state.userId, 'u1');
      await bloc.close();
    });

    test('a throwing sink does not break the others', () async {
      final bad = RecordingSink(throwOnEvent: true);
      final good = RecordingSink();
      final bloc = AnalyticsBloc.withConfig(AnalyticsConfig(sinks: [bad, good]));
      await settle();

      bloc.log('e', {});
      await settle();

      expect(good.events, ['e']); // good still got it
      expect(bloc.state.eventCount, 1);
      await bloc.close();
    });
  });

  group('Consent gate', () {
    test('events are dropped (counted) when consent is off', () async {
      final a = RecordingSink();
      final bloc = AnalyticsBloc.withConfig(
          AnalyticsConfig(sinks: [a], initiallyEnabled: false));
      await settle();

      bloc.log('e1', {});
      bloc.screen('S');
      await settle();

      expect(a.events, isEmpty);
      expect(a.screens, isEmpty);
      expect(bloc.state.droppedCount, 1); // the event; screen just drops
      expect(bloc.state.eventCount, 0);

      // Grant consent → subsequent events flow.
      bloc.setConsent(true);
      await settle();
      bloc.log('e2', {});
      await settle();
      expect(a.events, ['e2']);
      await bloc.close();
    });
  });

  group('Lifecycle', () {
    test('flush + close reach the sinks', () async {
      final a = RecordingSink();
      final bloc = AnalyticsBloc.withConfig(AnalyticsConfig(sinks: [a]));
      await settle();

      bloc.flush();
      await settle();
      expect(a.flushed, isTrue);

      await bloc.close();
      expect(a.disposed, isTrue);
    });
  });
}
