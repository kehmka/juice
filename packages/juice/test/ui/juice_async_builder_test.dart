import 'package:flutter_test/flutter_test.dart';
import 'package:juice/juice.dart';
import 'package:rxdart/rxdart.dart';

/// Pins for JuiceAsyncBuilder, the stream/future host under every Juice
/// widget: initial value, stream data/error/done, ValueStream seeding,
/// pause/resume, source swaps in didUpdateWidget, retain, futures, error
/// reporting, and keep-alive.

Widget _host(JuiceAsyncBuilder<int> b) => MaterialApp(home: b);

/// Stream/future callbacks land in fake-async microtasks; the resulting
/// ValueNotifier change needs one more frame to be built.
Future<void> _flush(WidgetTester t) async {
  await t.pump();
  await t.pump();
}

String _texts(WidgetTester t) =>
    t.widgetList<Text>(find.byType(Text)).map((w) => w.data).join('|');

void main() {
  group('stream source', () {
    testWidgets('shows initial, then each value; initiator runs once',
        (tester) async {
      final c = StreamController<int>();
      var inits = 0;
      JuiceAsyncBuilder<int> b() => JuiceAsyncBuilder<int>(
            stream: c.stream,
            initial: 1,
            initiator: () => inits++,
            builder: (_, v) => Text('v$v'),
          );
      await tester.pumpWidget(_host(b()));
      expect(_texts(tester), 'v1');
      c.add(2);
      await _flush(tester);
      expect(_texts(tester), 'v2');
      await tester.pumpWidget(_host(b())); // same stream: no resubscribe
      expect(_texts(tester), 'v2');
      expect(inits, 1);
      unawaited(c.close());
    });

    testWidgets('a null initial is rejected with ArgumentError',
        (tester) async {
      await tester.pumpWidget(_host(JuiceAsyncBuilder<int>(
        stream: const Stream<int>.empty(),
        builder: (_, v) => Text('v$v'),
      )));
      expect(tester.takeException(), isA<ArgumentError>());
    });

    testWidgets('error builder handles stream errors silently by default',
        (tester) async {
      final c = StreamController<int>();
      final reported = <FlutterErrorDetails>[];
      await tester.pumpWidget(_host(JuiceAsyncBuilder<int>(
        stream: c.stream,
        initial: 0,
        reportError: reported.add,
        builder: (_, v) => Text('v$v'),
        error: (_, v, e, s) => Text('err:$e@$v'),
      )));
      c.addError('bad');
      await _flush(tester);
      expect(_texts(tester), 'err:bad@0');
      expect(reported, isEmpty, reason: 'silent defaults to error != null');

      c.add(5); // recovers on the next value
      await _flush(tester);
      expect(_texts(tester), 'v5');
      unawaited(c.close());
    });

    testWidgets('without an error builder the error is reported',
        (tester) async {
      final c = StreamController<int>();
      final reported = <FlutterErrorDetails>[];
      await tester.pumpWidget(_host(JuiceAsyncBuilder<int>(
        stream: c.stream,
        initial: 3,
        reportError: reported.add,
        builder: (_, v) => Text('v$v'),
      )));
      c.addError(StateError('x'));
      await _flush(tester);
      expect(reported, hasLength(1));
      expect(reported.single.exception, isA<StateError>());
      expect(_texts(tester), 'v3', reason: 'falls back to initial');
      await tester.pumpWidget(const SizedBox()); // cancel before close
      unawaited(c.close());
    });

    testWidgets('silent: false reports even with an error builder',
        (tester) async {
      final c = StreamController<int>();
      final reported = <FlutterErrorDetails>[];
      await tester.pumpWidget(_host(JuiceAsyncBuilder<int>(
        stream: c.stream,
        initial: 0,
        silent: false,
        reportError: reported.add,
        builder: (_, v) => Text('v$v'),
        error: (_, v, e, s) => Text('err:$e'),
      )));
      c.addError('loud');
      await _flush(tester);
      expect(_texts(tester), 'err:loud');
      expect(reported, hasLength(1));
      await tester.pumpWidget(const SizedBox()); // cancel before close
      unawaited(c.close());
    });

    testWidgets('done renders closed() with the last value', (tester) async {
      final c = StreamController<int>();
      await tester.pumpWidget(_host(JuiceAsyncBuilder<int>(
        stream: c.stream,
        initial: 0,
        builder: (_, v) => Text('v$v'),
        closed: (_, v) => Text('closed$v'),
      )));
      c.add(9);
      await _flush(tester);
      unawaited(c.close());
      await _flush(tester);
      expect(_texts(tester), 'closed9');
    });

    testWidgets('done without closed() keeps the builder', (tester) async {
      final c = StreamController<int>();
      await tester.pumpWidget(_host(JuiceAsyncBuilder<int>(
        stream: c.stream,
        initial: 0,
        builder: (_, v) => Text('v$v'),
      )));
      c.add(4);
      await _flush(tester);
      unawaited(c.close());
      await _flush(tester);
      expect(_texts(tester), 'v4');
    });

    testWidgets('ValueStream: seeded value shows at once and is not replayed',
        (tester) async {
      final subject = BehaviorSubject<int>.seeded(7);
      final seen = <int>[];
      await tester.pumpWidget(_host(JuiceAsyncBuilder<int>(
        stream: subject,
        initial: 0,
        builder: (_, v) {
          seen.add(v);
          return Text('v$v');
        },
      )));
      expect(_texts(tester), 'v7');
      await _flush(tester);
      subject.add(8);
      await _flush(tester);
      expect(_texts(tester), 'v8');
      expect(seen, [7, 8], reason: 'the replayed seed is skipped');
      unawaited(subject.close());
    });

    testWidgets('pause buffers; unpausing via rebuild delivers',
        (tester) async {
      final c = StreamController<int>();
      JuiceAsyncBuilder<int> b(bool pause) => JuiceAsyncBuilder<int>(
            stream: c.stream,
            initial: 0,
            pause: pause,
            builder: (_, v) => Text('v$v'),
          );
      await tester.pumpWidget(_host(b(true)));
      c.add(1);
      await _flush(tester);
      expect(_texts(tester), 'v0', reason: 'paused');

      await tester.pumpWidget(_host(b(true))); // stays paused
      await tester.pumpWidget(_host(b(false)));
      await _flush(tester);
      expect(_texts(tester), 'v1');

      await tester.pumpWidget(_host(b(true))); // pause again
      c.add(2);
      await _flush(tester);
      expect(_texts(tester), 'v1');
      await tester.pumpWidget(_host(b(false)));
      await _flush(tester);
      expect(_texts(tester), 'v2');
      await tester.pumpWidget(const SizedBox());
      unawaited(c.close());
    });

    testWidgets('swapping the stream follows the new one only', (tester) async {
      final a = StreamController<int>.broadcast();
      final b = StreamController<int>.broadcast();
      JuiceAsyncBuilder<int> w(Stream<int> s) => JuiceAsyncBuilder<int>(
          stream: s, initial: 0, builder: (_, v) => Text('v$v'));
      await tester.pumpWidget(_host(w(a.stream)));
      a.add(1);
      await _flush(tester);
      expect(_texts(tester), 'v1');

      await tester.pumpWidget(_host(w(b.stream)));
      expect(_texts(tester), 'v0', reason: 'resets to initial on swap');
      a.add(100);
      b.add(2);
      await _flush(tester);
      expect(_texts(tester), 'v2');
      unawaited(a.close());
      unawaited(b.close());
    });

    testWidgets('removing the source: retain keeps the value, else resets',
        (tester) async {
      for (final retain in [true, false]) {
        final c = StreamController<int>();
        await tester.pumpWidget(_host(JuiceAsyncBuilder<int>(
            key: ValueKey(retain),
            stream: c.stream,
            initial: 0,
            retain: retain,
            builder: (_, v) => Text('v$v'))));
        c.add(6);
        await _flush(tester);
        await tester.pumpWidget(_host(JuiceAsyncBuilder<int>(
            key: ValueKey(retain),
            initial: 0,
            retain: retain,
            builder: (_, v) => Text('v$v'))));
        expect(_texts(tester), retain ? 'v6' : 'v0', reason: 'retain=$retain');
        c.add(7); // no longer subscribed
        await _flush(tester);
        expect(_texts(tester), retain ? 'v6' : 'v0');
        unawaited(c.close());
      }
    });
  });

  group('future source', () {
    testWidgets('shows initial, then the resolved value', (tester) async {
      final done = Completer<int>();
      await tester.pumpWidget(_host(JuiceAsyncBuilder<int>(
        future: done.future,
        initial: 0,
        builder: (_, v) => Text('v$v'),
      )));
      expect(_texts(tester), 'v0');
      done.complete(5);
      await _flush(tester);
      expect(_texts(tester), 'v5');
    });

    testWidgets('error goes to the error builder (silent)', (tester) async {
      final done = Completer<int>();
      final reported = <FlutterErrorDetails>[];
      await tester.pumpWidget(_host(JuiceAsyncBuilder<int>(
        future: done.future,
        initial: 0,
        reportError: reported.add,
        builder: (_, v) => Text('v$v'),
        error: (_, v, e, s) => Text('err:$e'),
      )));
      done.completeError('nope');
      await _flush(tester);
      expect(_texts(tester), 'err:nope');
      expect(reported, isEmpty);
    });

    testWidgets('error without an error builder is reported', (tester) async {
      final done = Completer<int>();
      final reported = <FlutterErrorDetails>[];
      await tester.pumpWidget(_host(JuiceAsyncBuilder<int>(
        future: done.future,
        initial: 2,
        reportError: reported.add,
        builder: (_, v) => Text('v$v'),
      )));
      done.completeError('nope');
      await _flush(tester);
      expect(reported.single.exception, 'nope');
      expect(_texts(tester), 'v2');
    });

    testWidgets('a superseded future\'s value is ignored', (tester) async {
      final first = Completer<int>();
      final second = Completer<int>();
      JuiceAsyncBuilder<int> w(Future<int> f) => JuiceAsyncBuilder<int>(
          future: f, initial: 0, builder: (_, v) => Text('v$v'));
      await tester.pumpWidget(_host(w(first.future)));
      await tester.pumpWidget(_host(w(first.future))); // same: no re-init
      await tester.pumpWidget(_host(w(second.future)));
      second.complete(2);
      await _flush(tester);
      first.complete(1);
      await _flush(tester);
      expect(_texts(tester), 'v2');
    });

    testWidgets('a value arriving after unmount is dropped', (tester) async {
      final done = Completer<int>();
      await tester.pumpWidget(_host(JuiceAsyncBuilder<int>(
          future: done.future, initial: 0, builder: (_, v) => Text('v$v'))));
      await tester.pumpWidget(const SizedBox());
      done.complete(1);
      await _flush(tester);
      expect(tester.takeException(), isNull);
    });

    testWidgets('switching stream -> future cancels the stream',
        (tester) async {
      final c = StreamController<int>.broadcast();
      final f = Completer<int>();
      await tester.pumpWidget(_host(JuiceAsyncBuilder<int>(
          stream: c.stream, initial: 0, builder: (_, v) => Text('v$v'))));
      expect(c.hasListener, isTrue);
      await tester.pumpWidget(_host(JuiceAsyncBuilder<int>(
          future: f.future, initial: 0, builder: (_, v) => Text('v$v'))));
      expect(c.hasListener, isFalse);
      f.complete(3);
      await _flush(tester);
      expect(_texts(tester), 'v3');
      unawaited(c.close());
    });
  });

  testWidgets('keepAlive is surfaced to AutomaticKeepAliveClientMixin',
      (tester) async {
    for (final keep in [true, false]) {
      await tester.pumpWidget(_host(JuiceAsyncBuilder<int>(
          key: ValueKey(keep),
          stream: const Stream<int>.empty(),
          initial: 0,
          keepAlive: keep,
          builder: (_, v) => Text('v$v'))));
      final state = tester.state(find.byType(JuiceAsyncBuilder<int>))
          as AutomaticKeepAliveClientMixin;
      // ignore: invalid_use_of_protected_member
      expect(state.wantKeepAlive, keep);
    }
  });

  group('1.9.0 fixes', () {
    testWidgets('a stream that closes right after an error does not throw',
        (tester) async {
      final c = StreamController<int>();
      await tester.pumpWidget(_host(JuiceAsyncBuilder<int>(
        stream: c.stream,
        initial: 0,
        builder: (_, v) => Text('v$v'),
        error: (_, v, e, s) => Text('err:$e'),
      )));
      c.addError('x');
      await _flush(tester);
      await c.close();
      await _flush(tester); // threw "Snapshot data must not be null"
      expect(tester.takeException(), isNull);
      expect(_texts(tester), 'err:x', reason: 'the error is kept, now done');
    });

    testWidgets('a future that fails after unmount is ignored', (tester) async {
      final completer = Completer<int>();
      await tester.pumpWidget(_host(JuiceAsyncBuilder<int>(
        future: completer.future,
        initial: 0,
        builder: (_, v) => Text('v$v'),
        error: (_, v, e, s) => Text('err:$e'),
      )));
      await tester.pumpWidget(const SizedBox());
      completer.completeError('late');
      await tester.pump(); // "ValueNotifier used after being disposed"
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'a replaced future\'s late error does not overwrite the new one',
        (tester) async {
      final first = Completer<int>();
      final second = Completer<int>();
      Widget w(Future<int> f) => _host(JuiceAsyncBuilder<int>(
            future: f,
            initial: 0,
            builder: (_, v) => Text('v$v'),
            error: (_, v, e, s) => Text('err:$e'),
          ));
      await tester.pumpWidget(w(first.future));
      await tester.pumpWidget(w(second.future));
      second.complete(7);
      await _flush(tester);
      first.completeError('stale');
      await _flush(tester);
      expect(_texts(tester), 'v7');
    });
  });
}
