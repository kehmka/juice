import 'dart:async';

import 'package:devtools_extensions/devtools_extensions.dart';
import 'package:vm_service/vm_service.dart' show Event;

import 'telemetry_model.dart';

export 'telemetry_model.dart';

/// [TelemetryModel] wired to the connected VM: subscribes to the extension
/// stream (the ServiceManager already streamListens 'Extension'), filters
/// `juice:` kinds, and re-subscribes whenever the connection flips so a
/// hot-restarted app keeps flowing.
class TelemetryStore extends TelemetryModel {
  StreamSubscription<Event>? _sub;

  bool get connected => serviceManager.connectedState.value.connected;

  void attach() {
    serviceManager.connectedState.addListener(_rewire);
    _rewire();
  }

  void _rewire() {
    _sub?.cancel();
    _sub = null;
    final service = serviceManager.service;
    if (service == null || !connected) {
      notifyListeners();
      return;
    }
    _sub = service.onExtensionEvent.listen((e) {
      final kind = e.extensionKind;
      if (kind == null || !kind.startsWith('juice:')) return;
      final data = Map<String, Object?>.from(e.extensionData?.data ?? const {});
      ingest(kind.substring('juice:'.length), data,
          at: e.timestamp != null
              ? DateTime.fromMillisecondsSinceEpoch(e.timestamp!)
              : DateTime.now());
    });
    notifyListeners();
  }

  @override
  void dispose() {
    _sub?.cancel();
    serviceManager.connectedState.removeListener(_rewire);
    super.dispose();
  }
}
