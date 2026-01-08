// ignore_for_file: must_be_immutable

import 'package:juice/juice.dart';
import 'package:juice_storage/juice_storage.dart';

import '../blocs/arcade_demo_bloc.dart';
import '../blocs/arcade_demo_events.dart';
import '../blocs/arcade_demo_state.dart';
import '../demo_entry.dart';
import '../widgets/capsule_card.dart';

/// Main screen for the Storage Arcade demo.
///
/// Demonstrates proper Juice patterns:
/// - [StatelessJuiceWidget2] observes both [StorageBloc] and [ArcadeDemoBloc]
/// - Cross-bloc communication via BlocScope
/// - Targeted rebuild groups for performance
class ArcadeScreen
    extends StatelessJuiceWidget2<StorageBloc, ArcadeDemoBloc> {
  ArcadeScreen({super.key})
      : super(
          groups: const {
            'storage:init',
            ArcadeDemoBloc.groupBanner,
            ArcadeDemoBloc.groupForm,
            ArcadeDemoBloc.groupEntries,
            ArcadeDemoBloc.groupTime,
          },
        );

  /// StorageBloc for checking initialization status.
  StorageBloc get storageBloc => bloc1;

  /// ArcadeDemoBloc for UI state management.
  ArcadeDemoBloc get arcadeBloc => bloc2;

  @override
  Widget onBuild(BuildContext context, StreamStatus status) {
    // Wait for storage initialization
    if (!storageBloc.state.isInitialized) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final state = arcadeBloc.state;
    final isReady = !state.isOperationInProgress;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Storage Arcade'),
        actions: [
          IconButton(
            tooltip: 'Spawn 3 time bombs',
            onPressed: isReady ? () => arcadeBloc.send(SpawnBombsEvent()) : null,
            icon: const Icon(Icons.casino),
          ),
          IconButton(
            tooltip: 'Run cache cleanup now',
            onPressed: isReady ? () => arcadeBloc.send(CleanupCacheEvent()) : null,
            icon: const Icon(Icons.cleaning_services),
          ),
        ],
      ),
      body: Column(
        children: [
          // Composer card
          _Composer(state: state, isReady: isReady),

          // Banner
          _Banner(),

          // Entry list
          Expanded(child: _EntryList()),
        ],
      ),
    );
  }
}

/// Banner showing last operation result.
class _Banner extends StatelessJuiceWidget<ArcadeDemoBloc> {
  _Banner() : super(groups: const {ArcadeDemoBloc.groupBanner});

  @override
  Widget onBuild(BuildContext context, StreamStatus status) {
    final banner = bloc.state.banner;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 200),
        child: Container(
          key: ValueKey(banner),
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
          ),
          child: Row(
            children: [
              const Icon(Icons.terminal, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  banner,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Entry list with countdown display.
class _EntryList extends StatelessJuiceWidget<ArcadeDemoBloc> {
  _EntryList() : super(groups: const {ArcadeDemoBloc.groupEntries, ArcadeDemoBloc.groupTime});

  @override
  Widget onBuild(BuildContext context, StreamStatus status) {
    final entries = bloc.state.entries;
    final now = bloc.state.now;

    if (entries.isEmpty) {
      return Center(
        child: Text(
          'No entries yet.\nSave something to see it here!',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: Theme.of(context).colorScheme.outline,
              ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      itemCount: entries.length,
      itemBuilder: (context, index) {
        final entry = entries[index];
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: CapsuleCard(
            entry: entry,
            now: now,
            onRead: () => bloc.send(ReadEntryEvent(entry.id)),
            onDelete: () => bloc.send(DeleteEntryEvent(entry.id)),
          ),
        );
      },
    );
  }
}

/// Composer widget for creating new storage entries.
class _Composer extends StatelessJuiceWidget<ArcadeDemoBloc> {
  _Composer({
    required this.state,
    required this.isReady,
  }) : super(groups: const {ArcadeDemoBloc.groupForm});

  final ArcadeDemoState state;
  final bool isReady;

  @override
  Widget onBuild(BuildContext context, StreamStatus status) {
    final ttlSupported = bloc.state.ttlSupported;
    final currentState = bloc.state;

    return Card(
      margin: const EdgeInsets.all(12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                DropdownButton<DemoBackend>(
                  value: currentState.selectedBackend,
                  onChanged: (v) =>
                      v == null ? null : bloc.send(SelectBackendEvent(v)),
                  items: DemoBackend.values
                      .map((b) => DropdownMenuItem(
                            value: b,
                            child: Text(b.name.toUpperCase()),
                          ))
                      .toList(),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: TextEditingController(text: currentState.keyText),
                    decoration: const InputDecoration(
                      labelText: 'Key',
                      isDense: true,
                    ),
                    onChanged: (v) => bloc.send(UpdateKeyEvent(v)),
                  ),
                ),
                const SizedBox(width: 12),
                FilledButton.icon(
                  onPressed: isReady ? () => bloc.send(SaveEntryEvent()) : null,
                  icon: const Icon(Icons.save, size: 18),
                  label: const Text('Save'),
                ),
              ],
            ),
            const SizedBox(height: 10),
            TextField(
              controller: TextEditingController(text: currentState.valueText),
              decoration: const InputDecoration(
                labelText: 'Value',
                isDense: true,
              ),
              maxLines: 1,
              onChanged: (v) => bloc.send(UpdateValueEvent(v)),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Text(
                  'TTL',
                  style: TextStyle(
                    color: ttlSupported ? null : Theme.of(context).disabledColor,
                  ),
                ),
                Expanded(
                  child: Slider(
                    value: currentState.ttlSeconds.clamp(0, 60),
                    min: 0,
                    max: 60,
                    divisions: 60,
                    label: currentState.ttlSeconds.round() == 0
                        ? 'None'
                        : '${currentState.ttlSeconds.round()}s',
                    onChanged:
                        ttlSupported ? (v) => bloc.send(UpdateTtlEvent(v)) : null,
                  ),
                ),
                SizedBox(
                  width: 48,
                  child: Text(
                    currentState.ttlSeconds.round() == 0
                        ? 'None'
                        : '${currentState.ttlSeconds.round()}s',
                    textAlign: TextAlign.end,
                    style: TextStyle(
                      color:
                          ttlSupported ? null : Theme.of(context).disabledColor,
                    ),
                  ),
                ),
              ],
            ),
            if (!ttlSupported)
              Text(
                currentState.selectedBackend == DemoBackend.secure
                    ? 'Secure storage: TTL not supported (by design)'
                    : 'SQLite: TTL not supported in this demo',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.outline,
                    ),
              ),
          ],
        ),
      ),
    );
  }
}
