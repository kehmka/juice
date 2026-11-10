import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:juice/juice.dart' show ResultEventOps;
import 'package:juice_permissions/juice_permissions.dart';

/// Pure-Dart fake provider — drives the bloc without any platform plugin.
class FakePermissionProvider implements PermissionProvider {
  /// What `request()` resolves to per permission (default granted).
  final Map<JuicePermission, PermissionStatus> requestResults;

  /// What `status()` resolves to per permission (default denied).
  final Map<JuicePermission, PermissionStatus> statuses;

  /// Optional delay so concurrent requests overlap (for singleflight tests).
  final Duration delay;

  final Map<JuicePermission, Completer<void>> statusGates = {};
  final Map<JuicePermission, Completer<void>> requestGates = {};
  final List<JuicePermission> statusStarts = [];
  final List<JuicePermission> requestStarts = [];
  Completer<void>? requestAllGate;
  Completer<bool>? openSettingsGate;

  int requestCalls = 0;
  int openSettingsCalls = 0;

  FakePermissionProvider({
    this.requestResults = const {},
    this.statuses = const {},
    this.delay = Duration.zero,
  });

  @override
  Future<PermissionStatus> status(JuicePermission p) async {
    statusStarts.add(p);
    final gate = statusGates[p];
    if (gate != null) await gate.future;
    return statuses[p] ?? PermissionStatus.denied;
  }

  @override
  Future<PermissionStatus> request(JuicePermission p) async {
    requestCalls++;
    requestStarts.add(p);
    final gate = requestGates[p];
    if (gate != null) await gate.future;
    if (delay > Duration.zero) await Future<void>.delayed(delay);
    return requestResults[p] ?? PermissionStatus.granted;
  }

  @override
  Future<Map<JuicePermission, PermissionStatus>> requestAll(
      Set<JuicePermission> ps) async {
    requestCalls++;
    final gate = requestAllGate;
    requestAllGate = null;
    if (gate != null) await gate.future;
    return {
      for (final p in ps) p: requestResults[p] ?? PermissionStatus.granted
    };
  }

  @override
  Future<bool> openSettings() async {
    openSettingsCalls++;
    final gate = openSettingsGate;
    openSettingsGate = null;
    if (gate != null) return gate.future;
    return true;
  }

  @override
  Future<void> dispose() async {}
}

/// A provider whose prompts fail once [gate] opens.
class BrokenPermissionProvider extends FakePermissionProvider {
  final gate = Completer<void>();

  @override
  Future<PermissionStatus> request(JuicePermission p) async {
    requestCalls++;
    await gate.future;
    throw StateError('prompt failed');
  }

  @override
  Future<Map<JuicePermission, PermissionStatus>> requestAll(
      Set<JuicePermission> ps) async {
    requestCalls++;
    await gate.future;
    throw StateError('batch failed');
  }
}

void main() {
  Future<void> settle([int ms = 30]) =>
      Future<void>.delayed(Duration(milliseconds: ms));

  const camera = JuicePermission.camera;
  const mic = JuicePermission.microphone;

  group('PermissionsState model', () {
    test('unknown by default', () {
      const s = PermissionsState();
      expect(s.statusOf(camera), PermissionStatus.unknown);
      expect(s.isGranted(camera), isFalse);
      expect(s.isUsable(camera), isFalse);
    });

    test('isUsable covers granted, limited, provisional', () {
      const s = PermissionsState(statuses: {
        JuicePermission.camera: PermissionStatus.limited,
        JuicePermission.photos: PermissionStatus.provisional,
        JuicePermission.contacts: PermissionStatus.granted,
        JuicePermission.microphone: PermissionStatus.denied,
      });
      expect(s.isUsable(JuicePermission.camera), isTrue);
      expect(s.isUsable(JuicePermission.photos), isTrue);
      expect(s.isUsable(JuicePermission.contacts), isTrue);
      expect(s.isUsable(JuicePermission.microphone), isFalse);
      // isGranted is strict.
      expect(s.isGranted(JuicePermission.camera), isFalse);
      expect(s.isGranted(JuicePermission.contacts), isTrue);
    });
  });

  group('PermissionsBloc', () {
    test('precheck reads statuses on init', () async {
      final p =
          FakePermissionProvider(statuses: {camera: PermissionStatus.granted});
      final bloc = PermissionsBloc.withConfig(
        PermissionsConfig(provider: p, precheck: {camera}),
      );
      await settle();

      expect(bloc.state.statusOf(camera), PermissionStatus.granted);
      await bloc.close();
    });

    test('check reads status without prompting', () async {
      final p =
          FakePermissionProvider(statuses: {camera: PermissionStatus.denied});
      final bloc = PermissionsBloc.withConfig(PermissionsConfig(provider: p));
      await settle();

      bloc.check(camera);
      await settle();

      expect(bloc.state.statusOf(camera), PermissionStatus.denied);
      expect(p.requestCalls, 0); // no prompt
      await bloc.close();
    });

    test('independent checks overlap and merge their results', () async {
      final cameraGate = Completer<void>();
      final micGate = Completer<void>();
      final p = FakePermissionProvider(statuses: {
        camera: PermissionStatus.granted,
        mic: PermissionStatus.denied,
      })
        ..statusGates[camera] = cameraGate
        ..statusGates[mic] = micGate;
      final bloc = PermissionsBloc.withConfig(PermissionsConfig(provider: p));
      await settle();

      bloc.check(camera);
      bloc.check(mic);
      await settle();
      expect(p.statusStarts, [camera, mic]);

      cameraGate.complete();
      micGate.complete();
      await settle();
      expect(bloc.state.statusOf(camera), PermissionStatus.granted);
      expect(bloc.state.statusOf(mic), PermissionStatus.denied);
      await bloc.close();
    });

    test('request grants and updates state', () async {
      final p = FakePermissionProvider(
          requestResults: {camera: PermissionStatus.granted});
      final bloc = PermissionsBloc.withConfig(PermissionsConfig(provider: p));
      await settle();

      bloc.request(camera);
      await settle();

      expect(bloc.state.isGranted(camera), isTrue);
      expect(bloc.state.isRequesting(camera), isFalse);
      await bloc.close();
    });

    test('request denial reflects in state', () async {
      final p = FakePermissionProvider(
          requestResults: {camera: PermissionStatus.permanentlyDenied});
      final bloc = PermissionsBloc.withConfig(PermissionsConfig(provider: p));
      await settle();

      bloc.request(camera);
      await settle();

      expect(bloc.state.isUsable(camera), isFalse);
      expect(bloc.state.isPermanentlyDenied(camera), isTrue);
      await bloc.close();
    });

    test('concurrent requests for the same permission collapse to one prompt',
        () async {
      final p = FakePermissionProvider(
        requestResults: {camera: PermissionStatus.granted},
        delay: const Duration(milliseconds: 80),
      );
      final bloc = PermissionsBloc.withConfig(PermissionsConfig(provider: p));
      await settle();

      // Fire several requests for the same permission back-to-back.
      bloc.request(camera);
      bloc.request(camera);
      bloc.request(camera);
      await settle(200);

      expect(p.requestCalls, 1); // singleflight collapsed them
      expect(bloc.state.isGranted(camera), isTrue);
      await bloc.close();
    });

    test('requests for different permissions remain concurrent', () async {
      final cameraGate = Completer<void>();
      final micGate = Completer<void>();
      final p = FakePermissionProvider(requestResults: {
        camera: PermissionStatus.granted,
        mic: PermissionStatus.denied,
      })
        ..requestGates[camera] = cameraGate
        ..requestGates[mic] = micGate;
      final bloc = PermissionsBloc.withConfig(PermissionsConfig(provider: p));
      await settle();

      bloc.request(camera);
      bloc.request(mic);
      await settle();
      expect(p.requestStarts, [camera, mic]);
      expect(bloc.state.inFlight, {camera, mic});

      cameraGate.complete();
      micGate.complete();
      await settle();
      expect(bloc.state.statusOf(camera), PermissionStatus.granted);
      expect(bloc.state.statusOf(mic), PermissionStatus.denied);
      expect(bloc.state.inFlight, isEmpty);
      await bloc.close();
    });

    test('requestAll prompts a batch and records all statuses', () async {
      final p = FakePermissionProvider(requestResults: {
        camera: PermissionStatus.granted,
        mic: PermissionStatus.denied,
      });
      final bloc = PermissionsBloc.withConfig(PermissionsConfig(provider: p));
      await settle();

      bloc.requestAll({camera, mic});
      await settle();

      expect(bloc.state.isGranted(camera), isTrue);
      expect(bloc.state.statusOf(mic), PermissionStatus.denied);
      await bloc.close();
    });

    test('overlapping batch requests run sequentially', () async {
      final gate = Completer<void>();
      final p = FakePermissionProvider(requestResults: {
        camera: PermissionStatus.granted,
        mic: PermissionStatus.denied,
      })
        ..requestAllGate = gate;
      final bloc = PermissionsBloc.withConfig(PermissionsConfig(provider: p));
      await settle();

      bloc.requestAll({camera});
      bloc.requestAll({mic});
      await settle();
      expect(p.requestCalls, 1);
      expect(bloc.state.inFlight, {camera});

      gate.complete();
      await settle();
      expect(p.requestCalls, 2);
      expect(bloc.state.statusOf(camera), PermissionStatus.granted);
      expect(bloc.state.statusOf(mic), PermissionStatus.denied);
      expect(bloc.state.inFlight, isEmpty);
      await bloc.close();
    });

    test('openAppSettings delegates to the provider', () async {
      final p = FakePermissionProvider();
      final bloc = PermissionsBloc.withConfig(PermissionsConfig(provider: p));
      await settle();

      bloc.openAppSettings();
      await settle();

      expect(p.openSettingsCalls, 1);
      await bloc.close();
    });

    test('duplicate openAppSettings calls are dropped while one is active',
        () async {
      final gate = Completer<bool>();
      final p = FakePermissionProvider()..openSettingsGate = gate;
      final bloc = PermissionsBloc.withConfig(PermissionsConfig(provider: p));
      await settle();

      bloc.openAppSettings();
      bloc.openAppSettings();
      await settle();
      expect(p.openSettingsCalls, 1);

      gate.complete(true);
      await settle();
      await bloc.close();
    });
  });

  group('PermissionBinding', () {
    test('emits initial status then forwards changes (deduped)', () async {
      final p = FakePermissionProvider(
        statuses: {camera: PermissionStatus.denied},
        requestResults: {camera: PermissionStatus.granted},
      );
      final bloc = PermissionsBloc.withConfig(
        PermissionsConfig(provider: p, precheck: {camera}),
      );
      await settle();

      final seen = <PermissionStatus>[];
      final binding = PermissionBinding(
        bloc,
        camera,
        onStatus: seen.add,
      )..start();

      // Initial status delivered on start.
      expect(seen, [PermissionStatus.denied]);

      // A change is forwarded.
      bloc.request(camera);
      await settle();
      expect(seen.last, PermissionStatus.granted);

      // A no-op check of an unrelated permission doesn't re-fire camera.
      final before = seen.length;
      bloc.check(mic);
      await settle();
      expect(seen.length, before);

      binding.dispose();
      await bloc.close();
    });

    test('emitInitial:false skips the initial callback', () async {
      final p =
          FakePermissionProvider(statuses: {camera: PermissionStatus.granted});
      final bloc = PermissionsBloc.withConfig(
        PermissionsConfig(provider: p, precheck: {camera}),
      );
      await settle();

      final seen = <PermissionStatus>[];
      final binding = PermissionBinding(bloc, camera,
          onStatus: seen.add, emitInitial: false)
        ..start();

      expect(seen, isEmpty);
      binding.dispose();
      await bloc.close();
    });
  });

  group('Typed results: sendForResult', () {
    test('RequestPermissionEvent returns the status the user left it in',
        () async {
      final p = FakePermissionProvider(requestResults: {
        camera: PermissionStatus.granted,
        mic: PermissionStatus.permanentlyDenied,
      });
      final bloc = PermissionsBloc.withConfig(PermissionsConfig(provider: p));
      await settle();

      expect(await bloc.sendForResult(RequestPermissionEvent(camera)),
          PermissionStatus.granted);
      expect(await bloc.sendForResult(RequestPermissionEvent(mic)),
          PermissionStatus.permanentlyDenied);
      expect(bloc.state.inFlight, isEmpty);
      await bloc.close();
    });

    test(
        'callers asking for the same permission while it prompts all get '
        'the one prompt\'s answer; another permission prompts beside it',
        () async {
      final cameraGate = Completer<void>();
      final p = FakePermissionProvider(requestResults: {
        camera: PermissionStatus.limited,
        mic: PermissionStatus.denied,
      })
        ..requestGates[camera] = cameraGate;
      final bloc = PermissionsBloc.withConfig(PermissionsConfig(provider: p));
      await settle();

      final first = bloc.sendForResult(RequestPermissionEvent(camera));
      final second = bloc.sendForResult(RequestPermissionEvent(camera));
      final other = bloc.sendForResult(RequestPermissionEvent(mic));

      expect(await other, PermissionStatus.denied,
          reason: 'not held up by the camera prompt');
      expect(p.requestStarts, [camera, mic], reason: 'one camera prompt');
      expect(bloc.state.inFlight, {camera});

      cameraGate.complete();
      expect(await Future.wait([first, second]),
          [PermissionStatus.limited, PermissionStatus.limited]);
      expect(p.requestCalls, 2);
      await bloc.close();
    });

    test('a prompt that fails throws to every caller that joined it', () async {
      final p = BrokenPermissionProvider();
      final bloc = PermissionsBloc.withConfig(PermissionsConfig(provider: p));
      await settle();

      final callers = [
        bloc.sendForResult(RequestPermissionEvent(camera)),
        bloc.sendForResult(RequestPermissionEvent(camera)),
      ];
      final outcomes = [
        for (final caller in callers)
          expectLater(
              caller,
              throwsA(isA<StateError>()
                  .having((e) => e.message, 'message', 'prompt failed'))),
      ];
      p.gate.complete();
      await Future.wait(outcomes);

      expect(p.requestCalls, 1);
      expect(bloc.state.inFlight, isEmpty);
      await bloc.close();
    });

    test('RequestPermissionsEvent returns the status of each permission',
        () async {
      final p = FakePermissionProvider(requestResults: {
        camera: PermissionStatus.granted,
        mic: PermissionStatus.denied,
      });
      final bloc = PermissionsBloc.withConfig(PermissionsConfig(provider: p));
      await settle();

      expect(await bloc.sendForResult(RequestPermissionsEvent({camera, mic})),
          {camera: PermissionStatus.granted, mic: PermissionStatus.denied});
      await bloc.close();
    });

    test(
        'RequestPermissionsEvent for no permissions prompts nothing and '
        'returns nothing', () async {
      final p = FakePermissionProvider();
      final bloc = PermissionsBloc.withConfig(PermissionsConfig(provider: p));
      await settle();
      final before = bloc.state;

      expect(await bloc.sendForResult(RequestPermissionsEvent({})), isEmpty);
      expect(p.requestCalls, 0);
      expect(bloc.state.statuses, before.statuses);
      expect(bloc.state.inFlight, isEmpty);
      await bloc.close();
    });

    test('a batch that fails throws', () async {
      final p = BrokenPermissionProvider();
      final bloc = PermissionsBloc.withConfig(PermissionsConfig(provider: p));
      await settle();

      final batch = bloc.sendForResult(RequestPermissionsEvent({camera, mic}));
      final outcome = expectLater(
          batch,
          throwsA(isA<StateError>()
              .having((e) => e.message, 'message', 'batch failed')));
      p.gate.complete();
      await outcome;
      expect(bloc.state.inFlight, isEmpty);
      await bloc.close();
    });

    test('the two events are still permissions events, and print as before',
        () {
      expect(RequestPermissionEvent(camera), isA<PermissionsEvent>());
      expect(RequestPermissionsEvent({camera}), isA<PermissionsEvent>());
      expect(
          RequestPermissionEvent(camera).toString(), 'RequestPermissionEvent');
      expect(RequestPermissionsEvent({camera}).toString(),
          'RequestPermissionsEvent');
    });
  });
}
