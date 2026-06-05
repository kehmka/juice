import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:juice_location/juice_location.dart';

/// Pure-Dart fake — drives the bloc without a device.
class FakeLocationSource implements LocationSource {
  final _controller = StreamController<GeoPosition>.broadcast();
  GeoPosition? currentValue;
  Object? currentError;
  bool disposed = false;

  @override
  Future<GeoPosition> current() async {
    if (currentError != null) throw currentError!;
    return currentValue!;
  }

  @override
  Stream<GeoPosition> positions() => _controller.stream;

  @override
  Future<void> dispose() async {
    disposed = true;
    await _controller.close();
  }

  void emit(GeoPosition p) => _controller.add(p);
}

GeoPosition pos(double lat, double lng) =>
    GeoPosition(latitude: lat, longitude: lng, timestamp: DateTime(2026));

void main() {
  Future<void> settle([int ms = 20]) =>
      Future<void>.delayed(Duration(milliseconds: ms));

  group('LocationState model', () {
    test('defaults', () {
      const s = LocationState();
      expect(s.current, isNull);
      expect(s.tracking, isFalse);
      expect(s.permissionGranted, isFalse);
    });
  });

  group('LocationBloc', () {
    test('getCurrent reads a one-shot position', () async {
      final src = FakeLocationSource()..currentValue = pos(1, 2);
      final bloc = LocationBloc.withConfig(LocationConfig(source: src));
      await settle();

      bloc.getCurrent();
      await settle();

      expect(bloc.state.current?.latitude, 1);
      expect(bloc.state.current?.longitude, 2);
      await bloc.close();
    });

    test('getCurrent surfaces an error', () async {
      final src = FakeLocationSource()..currentError = StateError('no fix');
      final bloc = LocationBloc.withConfig(LocationConfig(source: src));
      await settle();

      bloc.getCurrent();
      await settle();

      expect(bloc.state.lastError, contains('no fix'));
      await bloc.close();
    });

    test('startTracking streams positions; stopTracking ends it', () async {
      final src = FakeLocationSource();
      final bloc = LocationBloc.withConfig(LocationConfig(source: src));
      await settle();

      bloc.startTrackingUpdates();
      await settle();
      expect(bloc.state.tracking, isTrue);

      src.emit(pos(10, 20));
      await settle();
      expect(bloc.state.current?.latitude, 10);

      bloc.stopTrackingUpdates();
      await settle();
      expect(bloc.state.tracking, isFalse);

      // No more updates after stop.
      src.emit(pos(99, 99));
      await settle();
      expect(bloc.state.current?.latitude, 10); // unchanged
      await bloc.close();
    });

    test('setPermissionStatus updates state (deduped)', () async {
      final src = FakeLocationSource();
      final bloc = LocationBloc.withConfig(LocationConfig(source: src));
      await settle();

      bloc.setPermissionStatus(true);
      await settle();
      expect(bloc.state.permissionGranted, isTrue);
      await bloc.close();
    });

    test('close disposes the source', () async {
      final src = FakeLocationSource();
      final bloc = LocationBloc.withConfig(LocationConfig(source: src));
      await settle();

      await bloc.close();
      expect(src.disposed, isTrue);
    });
  });
}
