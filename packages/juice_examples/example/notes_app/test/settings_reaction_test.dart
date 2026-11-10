// NotesBloc reacts to SettingsBloc (see the react() call in NotesBloc's
// constructor). These run the app's real blocs over real storage — Hive in
// a temp directory (path_provider's documents directory is answered with
// it), SharedPreferences on its in-memory test store — on the real clock.
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:juice/juice.dart';
import 'package:juice_storage/juice_storage.dart';
import 'package:notes_app/blocs/notes/notes_bloc.dart';
import 'package:notes_app/blocs/notes/notes_events.dart';
import 'package:notes_app/blocs/settings/settings_bloc.dart';
import 'package:notes_app/blocs/settings/settings_events.dart';
import 'package:notes_app/blocs/settings/settings_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _patience = Duration(seconds: 5);

/// Completes when [settings] has finished its initial load. Call it in the
/// same synchronous stretch that created the bloc, before the load can emit.
Future<void> _loaded(SettingsBloc settings) => settings.stream
    .firstWhere((status) => status.event is LoadSettingsEvent)
    .timeout(_patience);

/// Completes when [notes] has handled one more [SettingsChangedEvent].
Future<void> _nextSettingsChange(NotesBloc notes) => notes.stream
    .firstWhere((status) => status.event is SettingsChangedEvent)
    .timeout(_patience);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory hiveDir;

  const pathProvider = MethodChannel('plugins.flutter.io/path_provider');

  setUpAll(() async {
    hiveDir = await Directory.systemTemp.createTemp('notes_app_test_');
    // Hive.initFlutter asks path_provider where documents live.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProvider, (call) async {
      if (call.method == 'getApplicationDocumentsDirectory') {
        return hiveDir.path;
      }
      throw MissingPluginException('${call.method} is not answered here');
    });
    SharedPreferences.setMockInitialValues({});

    // The registrations main() makes. Storage is opened once for the file,
    // as the app opens it once for the process: juice_storage keeps its
    // open boxes and its prefs handle for the life of the process.
    BlocScope.register<StorageBloc>(
      () => StorageBloc(
        config: const StorageConfig(
          hiveBoxesToOpen: ['notes', 'trash'],
        ),
      ),
      lifecycle: BlocLifecycle.permanent,
    );
    await BlocScope.get<StorageBloc>().initialize();

    BlocScope.register<SettingsBloc>(
      () => SettingsBloc(),
      lifecycle: BlocLifecycle.permanent,
    );
    BlocScope.register<NotesBloc>(
      () => NotesBloc(),
      lifecycle: BlocLifecycle.permanent,
    );
  });

  // Every test gets a fresh NotesBloc and SettingsBloc (ending a permanent
  // bloc keeps its registration; the next get builds a new one) over
  // settings that were never saved.
  tearDown(() async {
    await BlocScope.end<NotesBloc>();
    await BlocScope.end<SettingsBloc>();
    final storage = BlocScope.get<StorageBloc>();
    await storage.prefsDelete('view_mode');
    await storage.prefsDelete('sort_order');
  });

  tearDownAll(() async {
    await BlocScope.reset();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProvider, null);
    await hiveDir.delete(recursive: true);
  });

  test('storage is ready: the Hive and prefs backends initialised', () {
    final status = BlocScope.get<StorageBloc>().state.backendStatus;
    expect(status.hive, BackendState.ready);
    expect(status.prefs, BackendState.ready);
  });

  test('a new sort order in SettingsBloc reaches NotesBloc', () async {
    final notes = BlocScope.get<NotesBloc>();
    final settings = BlocScope.get<SettingsBloc>();
    await _loaded(settings);

    settings.send(ChangeSortOrderEvent(sortOrder: SortOrder.titleAsc));

    final state = await notes.waitFor((s) => s.sortOrder == SortOrder.titleAsc,
        timeout: _patience);
    expect(state.viewMode, ViewMode.list);
  });

  test('a view mode toggle in SettingsBloc reaches NotesBloc', () async {
    final notes = BlocScope.get<NotesBloc>();
    final settings = BlocScope.get<SettingsBloc>();
    await _loaded(settings);

    settings.send(ToggleViewModeEvent());

    final state = await notes.waitFor((s) => s.viewMode == ViewMode.grid,
        timeout: _patience);
    expect(state.sortOrder, SortOrder.updatedDesc);
  });

  test(
      'catch-up: settings changed BEFORE NotesBloc exists still reach it '
      '— NotesBloc does not depend on which bloc was built first', () async {
    final settings = BlocScope.get<SettingsBloc>();
    await _loaded(settings);
    settings.send(ToggleViewModeEvent());
    settings.send(ChangeSortOrderEvent(sortOrder: SortOrder.titleDesc));
    await settings.waitFor(
        (s) =>
            s.viewMode == ViewMode.grid && s.sortOrder == SortOrder.titleDesc,
        timeout: _patience);

    final notes = BlocScope.get<NotesBloc>();
    expect(notes.state.viewMode, ViewMode.list,
        reason: 'catch-up is a hop, sent a microtask after the attach');

    final state = await notes.waitFor(
        (s) =>
            s.viewMode == ViewMode.grid && s.sortOrder == SortOrder.titleDesc,
        timeout: _patience);
    expect(state.viewMode, ViewMode.grid);
  });

  test(
      'a SettingsBloc emission that changes neither value sends NotesBloc '
      'nothing; the next real change sends exactly one event', () async {
    final notes = BlocScope.get<NotesBloc>();
    final caughtUp = _nextSettingsChange(notes);
    final settings = BlocScope.get<SettingsBloc>();
    await _loaded(settings);
    await caughtUp;

    var received = 0;
    final sub = notes.stream
        .where((status) => status.event is SettingsChangedEvent)
        .listen((_) => received++);
    addTearDown(sub.cancel);

    // Same order as the one already held: SettingsBloc emits, nothing moved.
    var emitted = 0;
    final emissions = settings.stream.listen((_) => emitted++);
    addTearDown(emissions.cancel);
    await settings
        .sendAndWait(ChangeSortOrderEvent(sortOrder: SortOrder.updatedDesc));
    await pumpEventQueue();
    expect(emitted, 1, reason: 'SettingsBloc did emit');
    expect(received, 0);

    settings.send(ChangeSortOrderEvent(sortOrder: SortOrder.updatedAsc));
    await notes.waitFor((s) => s.sortOrder == SortOrder.updatedAsc,
        timeout: _patience);
    await pumpEventQueue();
    expect(received, 1);
  });

  test('the reaction ends with NotesBloc: a later settings change is not sent',
      () async {
    final notes = BlocScope.get<NotesBloc>();
    final caughtUp = _nextSettingsChange(notes);
    final settings = BlocScope.get<SettingsBloc>();
    await _loaded(settings);
    await caughtUp;

    await BlocScope.end<NotesBloc>();
    expect(notes.isClosed, isTrue);

    await settings
        .sendAndWait(ChangeSortOrderEvent(sortOrder: SortOrder.titleAsc));
    await pumpEventQueue();
    expect(settings.state.sortOrder, SortOrder.titleAsc);
    expect(notes.state.sortOrder, SortOrder.updatedDesc);
  });
}
