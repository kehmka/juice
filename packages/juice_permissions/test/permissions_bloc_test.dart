import 'package:flutter_test/flutter_test.dart';
import 'package:juice_permissions/juice_permissions.dart';

/// Pure-Dart fake provider — drives the bloc without any platform plugin.
class FakePermissionProvider implements PermissionProvider {
  /// What `request()` resolves to per permission (default granted).
  final Map<JuicePermission, PermissionStatus> requestResults;

  /// What `status()` resolves to per permission (default denied).
  final Map<JuicePermission, PermissionStatus> statuses;

  /// Optional delay so concurrent requests overlap (for singleflight tests).
  final Duration delay;

  int requestCalls = 0;
  int openSettingsCalls = 0;

  FakePermissionProvider({
    this.requestResults = const {},
    this.statuses = const {},
    this.delay = Duration.zero,
  });

  @override
  Future<PermissionStatus> status(JuicePermission p) async =>
      statuses[p] ?? PermissionStatus.denied;

  @override
  Future<PermissionStatus> request(JuicePermission p) async {
    requestCalls++;
    if (delay > Duration.zero) await Future<void>.delayed(delay);
    return requestResults[p] ?? PermissionStatus.granted;
  }

  @override
  Future<Map<JuicePermission, PermissionStatus>> requestAll(
      Set<JuicePermission> ps) async {
    requestCalls++;
    return {for (final p in ps) p: requestResults[p] ?? PermissionStatus.granted};
  }

  @override
  Future<bool> openSettings() async {
    openSettingsCalls++;
    return true;
  }

  @override
  Future<void> dispose() async {}
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
      final p = FakePermissionProvider(
          statuses: {camera: PermissionStatus.granted});
      final bloc = PermissionsBloc.withConfig(
        PermissionsConfig(provider: p, precheck: {camera}),
      );
      await settle();

      expect(bloc.state.statusOf(camera), PermissionStatus.granted);
      await bloc.close();
    });

    test('check reads status without prompting', () async {
      final p = FakePermissionProvider(
          statuses: {camera: PermissionStatus.denied});
      final bloc = PermissionsBloc.withConfig(PermissionsConfig(provider: p));
      await settle();

      bloc.check(camera);
      await settle();

      expect(bloc.state.statusOf(camera), PermissionStatus.denied);
      expect(p.requestCalls, 0); // no prompt
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

    test('openAppSettings delegates to the provider', () async {
      final p = FakePermissionProvider();
      final bloc = PermissionsBloc.withConfig(PermissionsConfig(provider: p));
      await settle();

      bloc.openAppSettings();
      await settle();

      expect(p.openSettingsCalls, 1);
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
      final p = FakePermissionProvider(
          statuses: {camera: PermissionStatus.granted});
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
}
