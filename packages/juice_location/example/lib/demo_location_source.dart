import 'dart:async';
import 'dart:math' as math;

import 'package:juice_location/juice_location.dart';

/// A [LocationSource] that emits a wandering position on a timer, so the demo
/// runs with no device/GPS. The same seam the real `GeolocatorLocationSource`
/// plugs into.
class DemoLocationSource implements LocationSource {
  final _controller = StreamController<GeoPosition>.broadcast();
  Timer? _timer;
  double _lat = 37.7749; // San Francisco-ish
  double _lng = -122.4194;
  int _tick = 0;

  DemoLocationSource() {
    _timer = Timer.periodic(const Duration(seconds: 2), (_) {
      _tick++;
      _lat += 0.0008 * math.sin(_tick.toDouble());
      _lng += 0.0008 * math.cos(_tick.toDouble());
      _controller.add(_fix());
    });
  }

  GeoPosition _fix() => GeoPosition(
        latitude: _lat,
        longitude: _lng,
        accuracy: 12,
        timestamp: DateTime.fromMillisecondsSinceEpoch(_tick * 2000),
      );

  @override
  Future<GeoPosition> current() async => _fix();

  @override
  Stream<GeoPosition> positions() => _controller.stream;

  @override
  Future<void> dispose() async {
    _timer?.cancel();
    await _controller.close();
  }
}
