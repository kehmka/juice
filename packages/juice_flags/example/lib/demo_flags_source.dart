import 'dart:async';

import 'package:juice_flags/juice_flags.dart';

/// Demo source so the app runs with no backend. Stands in for a remote source
/// (e.g. a Firebase Remote Config adapter): it serves an initial map and then
/// flips `promo_banner` every few seconds over the live stream — so you can
/// watch only that flag's widget rebuild.
class DemoFlagsSource implements FlagsSource {
  final _controller = StreamController<Map<String, Object?>>.broadcast();
  Timer? _timer;
  bool _promo = false;

  final Map<String, Object?> _base = {
    'new_layout': true,
    'max_items': 25,
    'greeting': 'Welcome',
  };

  @override
  Future<Map<String, Object?>> fetch() async {
    await Future<void>.delayed(const Duration(milliseconds: 200));
    return {..._base, 'promo_banner': _promo};
  }

  @override
  Stream<Map<String, Object?>>? changes() {
    _timer ??= Timer.periodic(const Duration(seconds: 3), (_) {
      _promo = !_promo;
      _controller.add({..._base, 'promo_banner': _promo});
    });
    return _controller.stream;
  }

  @override
  Future<void> dispose() async {
    _timer?.cancel();
    await _controller.close();
  }
}
