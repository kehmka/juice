import 'package:flutter_test/flutter_test.dart';
import 'package:juice/juice.dart';
import 'package:juice_analytics/juice_analytics.dart';

class RecordingSink implements AnalyticsSink {
  final List<String> events = [];
  final List<String> screens = [];
  final List<String?> users = [];
  String? user;
  bool flushed = false;
  int flushCount = 0;
  bool disposed = false;
  final bool throwOnEvent;
  Completer<void>? eventGate;
  Completer<void>? screenGate;
  Completer<void>? userGate;
  Completer<void>? flushGate;
  RecordingSink({this.throwOnEvent = false});

  @override
  Future<void> logEvent(String name, Map<String, Object?> params) async {
    if (throwOnEvent) throw StateError('bad sink');
    events.add(name);
    await eventGate?.future;
  }

  @override
  Future<void> setScreen(String name) async {
    screens.add(name);
    await screenGate?.future;
  }

  @override
  Future<void> setUser(String? userId, Map<String, Object?> traits) async {
    user = userId;
    users.add(userId);
    await userGate?.future;
  }

  @override
  Future<void> flush() async {
    flushed = true;
    flushCount++;
    await flushGate?.future;
  }

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
      final bloc =
          AnalyticsBloc.withConfig(AnalyticsConfig(sinks: [bad, good]));
      await settle();

      bloc.log('e', {});
      await settle();

      expect(good.events, ['e']); // good still got it
      expect(bloc.state.eventCount, 1);
      await bloc.close();
    });

    test('same-type async sink calls stay in send order', () async {
      final sink = RecordingSink();
      final bloc = AnalyticsBloc.withConfig(AnalyticsConfig(sinks: [sink]));
      await settle();

      final eventGate = Completer<void>();
      sink.eventGate = eventGate;
      bloc.log('first');
      await settle(1);
      bloc.log('second');
      await settle(1);
      expect(sink.events, ['first'],
          reason: 'the second event waits for the first vendor call');
      eventGate.complete();
      await settle();
      expect(sink.events, ['first', 'second']);
      expect(bloc.state.eventCount, 2);

      final screenGate = Completer<void>();
      sink.screenGate = screenGate;
      bloc.screen('First');
      await settle(1);
      bloc.screen('Second');
      await settle(1);
      expect(sink.screens, ['First']);
      screenGate.complete();
      await settle();
      expect(sink.screens, ['First', 'Second']);
      expect(bloc.state.screenName, 'Second');

      final userGate = Completer<void>();
      sink.userGate = userGate;
      bloc.setUser('u1');
      await settle(1);
      bloc.setUser('u2');
      await settle(1);
      expect(sink.users, ['u1']);
      userGate.complete();
      await settle();
      expect(sink.users, ['u1', 'u2']);
      expect(bloc.state.userId, 'u2');

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
    test('overlapping flushes are coalesced', () async {
      final sink = RecordingSink();
      final bloc = AnalyticsBloc.withConfig(AnalyticsConfig(sinks: [sink]));
      await settle();

      final gate = Completer<void>();
      sink.flushGate = gate;
      bloc.flush();
      await settle(1);
      bloc.flush();
      await settle(1);

      expect(sink.flushCount, 1,
          reason: 'one in-flight flush already covers every sink');
      gate.complete();
      await settle();
      expect(sink.flushCount, 1);
      await bloc.close();
    });

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
