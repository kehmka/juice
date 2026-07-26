import 'package:flutter_test/flutter_test.dart';
import 'package:juice/juice.dart';
import 'package:juice_power/juice_power.dart';

/// Pure-Dart fake provider — drives the bloc without any platform plugin.
class FakePowerProvider implements PowerProvider {
  final _ctrl = StreamController<PowerSnapshot>.broadcast();
  PowerSnapshot _current;
  bool disposed = false;
  int checks = 0;

  FakePowerProvider(
      [this._current = const PowerSnapshot(
        status: BatteryStatus.discharging,
        percent: 80,
      )]);

  @override
  Stream<PowerSnapshot> get changes => _ctrl.stream;

  @override
  Future<PowerSnapshot> check() async {
    checks++;
    return _current;
  }

  @override
  Future<void> dispose() async {
    disposed = true;
    await _ctrl.close();
  }

  /// Push a new reading through the change stream.
  void emit(PowerSnapshot s) {
    _current = s;
    _ctrl.add(s);
  }

  /// Change what [check] will answer, without announcing it — how a charge
  /// level really moves: silently, between status changes.
  void setSilently(PowerSnapshot s) => _current = s;
}

void main() {
  PowerConfig cfg(
    FakePowerProvider p, {
    Duration pollInterval = Duration.zero,
  }) =>
      PowerConfig(provider: p, pollInterval: pollInterval);

  Future<void> settle([int ms = 30]) =>
      Future<void>.delayed(Duration(milliseconds: ms));

  group('PowerState model', () {
    test('defaults to unknown, and unknown is NOT plugged in', () {
      const s = PowerState();
      expect(s.status, BatteryStatus.unknown);
      expect(s.percent, isNull);
      expect(s.saverOn, isNull);
      expect(s.saverAsked, isFalse);
      // The load-bearing default: before the first reading, "may I burn
      // power?" must answer no. A true here would let expensive work start on
      // battery during every cold boot.
      expect(s.isPluggedIn, isFalse);
      expect(s.isOnBattery, isFalse);
    });

    test('isPluggedIn covers every connected status, including holding', () {
      for (final st in [
        BatteryStatus.charging,
        BatteryStatus.full,
        // iOS reports this when plugged in but deliberately not gaining
        // (optimized charging, a thermal hold, a weak source). The cable is
        // in; the wall is paying. Treating it as battery would stop work on a
        // charging desk overnight.
        BatteryStatus.connectedNotCharging,
      ]) {
        expect(PowerState(status: st).isPluggedIn, isTrue, reason: '$st');
        expect(PowerState(status: st).isOnBattery, isFalse, reason: '$st');
      }
    });

    test('isOnBattery is discharging only', () {
      expect(
          const PowerState(status: BatteryStatus.discharging).isOnBattery,
          isTrue);
      expect(const PowerState(status: BatteryStatus.unknown).isOnBattery,
          isFalse);
    });

    group('isAtOrBelow', () {
      test('compares when the level is known', () {
        const s = PowerState(percent: 20);
        expect(s.isAtOrBelow(20), isTrue); // inclusive
        expect(s.isAtOrBelow(21), isTrue);
        expect(s.isAtOrBelow(19), isFalse);
      });

      test('is FALSE when the level is unknown, never a guess', () {
        // An unknown level must not read as an empty one. The Simulator
        // answers -1 and some devices throw; if that became "0%", every gate
        // in every consumer would slam shut on a full battery.
        const s = PowerState(percent: null);
        expect(s.isAtOrBelow(20), isFalse);
        expect(s.isAtOrBelow(100), isFalse);
      });
    });

    group('saverAsked', () {
      test('true only when the keeper positively asked', () {
        expect(const PowerState(saverOn: true).saverAsked, isTrue);
        expect(const PowerState(saverOn: false).saverAsked, isFalse);
        // Unknown reads as "has not asked" — but as a choice made HERE, in the
        // open, rather than a `false` fabricated inside the provider where no
        // consumer could see it.
        expect(const PowerState(saverOn: null).saverAsked, isFalse);
      });
    });

    test('copyWith can CLEAR the level, not just replace it', () {
      const s = PowerState(status: BatteryStatus.discharging, percent: 55);
      expect(s.copyWith().percent, 55, reason: 'omitted → unchanged');
      expect(s.copyWith(percent: 40).percent, 40);
      // Without the sentinel, `percent ?? this.percent` makes null mean
      // "unchanged" — a device that stops reporting would serve 55 forever.
      expect(s.copyWith(percent: null).percent, isNull);
      expect(s.copyWith(percent: null).status, BatteryStatus.discharging,
          reason: 'clearing one field must not disturb another');
    });

    test('copyWith can CLEAR the saver flag too', () {
      const s = PowerState(saverOn: true, percent: 55);
      expect(s.copyWith().saverOn, isTrue, reason: 'omitted → unchanged');
      expect(s.copyWith(saverOn: false).saverOn, isFalse);
      expect(s.copyWith(saverOn: null).saverOn, isNull);
      expect(s.copyWith(saverOn: null).percent, 55);
    });
  });

  group('PowerBloc', () {
    test('emits an immediate first reading on initialize', () async {
      final p = FakePowerProvider(const PowerSnapshot(
          status: BatteryStatus.charging, percent: 42, saverOn: true));
      final bloc = PowerBloc.withConfig(cfg(p));
      await settle();

      // Without this, a consumer that boots and asks "may I run?" would see
      // PowerState.initial — unknown, reading as unplugged — and stall until
      // the next physical power change, which on a desk may be hours.
      expect(bloc.state.status, BatteryStatus.charging);
      expect(bloc.state.percent, 42);
      expect(bloc.state.saverOn, isTrue);
      expect(bloc.state.isPluggedIn, isTrue);
      await bloc.close();
    });

    test('a provider change reaches state', () async {
      final p = FakePowerProvider();
      final bloc = PowerBloc.withConfig(cfg(p));
      await settle();
      expect(bloc.state.isPluggedIn, isFalse);

      p.emit(const PowerSnapshot(
          status: BatteryStatus.charging, percent: 81));
      await settle();

      expect(bloc.state.isPluggedIn, isTrue);
      expect(bloc.state.percent, 81);
      await bloc.close();
    });

    test('an unchanged reading emits nothing', () async {
      final p = FakePowerProvider();
      final bloc = PowerBloc.withConfig(cfg(p));
      await settle();

      final seen = <StreamStatus<PowerState>>[];
      final sub = bloc.stream.listen(seen.add);

      // The level poll re-reads every minute; most reads find nothing new.
      // Emitting anyway would wake every consumer for a number that did not
      // move.
      p.emit(const PowerSnapshot(
          status: BatteryStatus.discharging, percent: 80));
      await settle();

      expect(seen, isEmpty);
      await sub.cancel();
      await bloc.close();
    });

    test('each kind of change emits only its own group', () async {
      final p = FakePowerProvider();
      final bloc = PowerBloc.withConfig(cfg(p));
      await settle();

      final groups = <Set<String>>[];
      final sub = bloc.stream.listen((s) {
        final g = s.event?.groupsToRebuild;
        if (g != null) groups.add(g.toSet());
      });

      p.emit(const PowerSnapshot(
          status: BatteryStatus.discharging, percent: 79)); // level only
      await settle();
      p.emit(const PowerSnapshot(
          status: BatteryStatus.charging, percent: 79)); // source only
      await settle();
      p.emit(const PowerSnapshot(
          status: BatteryStatus.charging, percent: 79, saverOn: true));
      await settle();

      expect(groups, [
        {PowerGroups.level},
        {PowerGroups.source},
        {PowerGroups.saver},
      ]);
      await sub.cancel();
      await bloc.close();
    });

    test('one reading that moves everything emits all three groups', () async {
      final p = FakePowerProvider();
      final bloc = PowerBloc.withConfig(cfg(p));
      await settle();

      final groups = <Set<String>>[];
      final sub = bloc.stream.listen((s) {
        final g = s.event?.groupsToRebuild;
        if (g != null) groups.add(g.toSet());
      });

      p.emit(const PowerSnapshot(
          status: BatteryStatus.charging, percent: 90, saverOn: true));
      await settle();

      expect(groups.single, PowerGroups.all);
      await sub.cancel();
      await bloc.close();
    });

    test('polling catches a level that moved with no status change', () async {
      final p = FakePowerProvider();
      final bloc = PowerBloc.withConfig(
          cfg(p, pollInterval: const Duration(milliseconds: 40)));
      await settle();
      expect(bloc.state.percent, 80);

      // This is the whole reason polling exists: platforms broadcast
      // plugged/unplugged but not the percentage, so a level gate would
      // otherwise act on a number frozen at the last cable event.
      p.setSilently(const PowerSnapshot(
          status: BatteryStatus.discharging, percent: 60));
      await settle(120);

      expect(bloc.state.percent, 60);
      await bloc.close();
    });

    test('pollInterval zero disables polling', () async {
      final p = FakePowerProvider();
      final bloc = PowerBloc.withConfig(cfg(p));
      await settle();
      final after = p.checks;

      p.setSilently(const PowerSnapshot(
          status: BatteryStatus.discharging, percent: 60));
      await settle(120);

      expect(p.checks, after, reason: 'no further reads');
      expect(bloc.state.percent, 80, reason: 'state stays at the last reading');
      await bloc.close();
    });

    test('check() re-reads on demand', () async {
      final p = FakePowerProvider();
      final bloc = PowerBloc.withConfig(cfg(p));
      await settle();

      p.setSilently(const PowerSnapshot(
          status: BatteryStatus.charging, percent: 95));
      bloc.check();
      await settle();

      expect(bloc.state.isPluggedIn, isTrue);
      expect(bloc.state.percent, 95);
      await bloc.close();
    });

    test('a level going unknown CLEARS it rather than serving a stale one',
        () async {
      final p = FakePowerProvider();
      final bloc = PowerBloc.withConfig(cfg(p));
      await settle();
      expect(bloc.state.percent, 80);

      p.emit(const PowerSnapshot(
          status: BatteryStatus.discharging, percent: null));
      await settle();

      expect(bloc.state.percent, isNull);
      expect(bloc.state.isAtOrBelow(20), isFalse,
          reason: 'unknown must not read as empty');
      await bloc.close();
    });

    test('close() stops the poll and disposes the provider', () async {
      final p = FakePowerProvider();
      final bloc = PowerBloc.withConfig(
          cfg(p, pollInterval: const Duration(milliseconds: 20)));
      await settle();

      await bloc.close();
      final after = p.checks;
      await settle(80);

      expect(p.disposed, isTrue);
      expect(p.checks, after, reason: 'a live timer after close leaks');
    });
  });
}
