import 'package:flutter/material.dart';

import 'telemetry_store.dart';
import 'views.dart';

/// The extension's root: a header (connection, counts, filter, clear) and
/// four tabs — Timeline, Spans, Blocs, Problems.
class JuicePanel extends StatefulWidget {
  const JuicePanel({super.key});

  @override
  State<JuicePanel> createState() => _JuicePanelState();
}

class _JuicePanelState extends State<JuicePanel> {
  final store = TelemetryStore();
  final filter = TextEditingController();

  @override
  void initState() {
    super.initState();
    store.attach();
  }

  @override
  void dispose() {
    store.dispose();
    filter.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 4,
      child: AnimatedBuilder(
        animation: Listenable.merge([store, filter]),
        builder: (context, _) {
          final theme = Theme.of(context);
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                child: Row(children: [
                  Icon(store.connected ? Icons.link : Icons.link_off,
                      size: 16,
                      color: store.connected
                          ? theme.colorScheme.primary
                          : theme.disabledColor),
                  const SizedBox(width: 8),
                  Text(store.connected
                      ? '${store.events.length} events · '
                          '${store.spans.length} spans · '
                          '${store.blocs.length} blocs'
                          '${store.problemCount > 0 ? ' · ${store.problemCount} problems' : ''}'
                      : 'no connected app — events appear when a Juice app '
                          'with DevtoolsJuiceLogger connects'),
                  const Spacer(),
                  SizedBox(
                    width: 220,
                    child: TextField(
                      controller: filter,
                      decoration: const InputDecoration(
                        isDense: true,
                        prefixIcon: Icon(Icons.filter_alt_outlined, size: 16),
                        hintText: 'filter (bloc, use case, kind)',
                        border: OutlineInputBorder(),
                      ),
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                  const SizedBox(width: 8),
                  TextButton.icon(
                    onPressed: store.clear,
                    icon: const Icon(Icons.clear_all, size: 16),
                    label: const Text('clear'),
                  ),
                ]),
              ),
              TabBar(tabs: [
                const Tab(text: 'Timeline'),
                const Tab(text: 'Spans'),
                const Tab(text: 'Blocs'),
                Tab(
                    text: store.problemCount > 0
                        ? 'Problems (${store.problemCount})'
                        : 'Problems'),
              ]),
              Expanded(
                child: TabBarView(children: [
                  TimelineView(store: store, filter: filter.text),
                  SpansView(store: store, filter: filter.text),
                  BlocsView(store: store, filter: filter.text),
                  ProblemsView(store: store, filter: filter.text),
                ]),
              ),
            ],
          );
        },
      ),
    );
  }
}
