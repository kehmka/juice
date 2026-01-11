import 'package:juice/juice.dart';
import '../lifecycle_demo_bloc.dart';
import '../lifecycle_demo_state.dart';
import '../lifecycle_demo_events.dart';
import 'task_card.dart';

/// Demo page showing LifecycleBloc's cleanup capabilities.
class LifecycleDemoPage extends StatelessWidget {
  const LifecycleDemoPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('LifecycleBloc Demo'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  _ExplanationHeader(),
                  _PhaseIndicator(),
                  _ControlPanel(),
                  _TaskSummary(),
                  _TaskGrid(),
                ],
              ),
            ),
          ),
          _EventLog(),
        ],
      ),
    );
  }
}

/// Header explaining what this demo shows.
class _ExplanationHeader extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      color: Colors.blue.shade50,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.info_outline, color: Colors.blue.shade700, size: 20),
              const SizedBox(width: 8),
              Text(
                'What This Demo Shows',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.blue.shade900,
                  fontSize: 14,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'LifecycleBloc provides deterministic cleanup when a feature scope ends. '
            'When you press "End Scope", in-flight tasks are canceled via CleanupBarrier '
            'before the scope fully closes.',
            style: TextStyle(
              color: Colors.blue.shade800,
              fontSize: 13,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

/// Visual indicator of the current lifecycle phase.
class _PhaseIndicator extends StatelessJuiceWidget<LifecycleDemoBloc> {
  _PhaseIndicator() : super(groups: const {LifecycleDemoGroups.controls});

  @override
  Widget onBuild(BuildContext context, StreamStatus status) {
    final state = bloc.state;

    // Determine which phase we're in
    final isIdle = !state.scopeActive && !state.scopeEnding && !state.scopeEnded;
    final isActive = state.scopeActive && !state.scopeEnding;
    final isEnding = state.scopeEnding;
    final isEnded = state.scopeEnded;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      color: Colors.grey.shade100,
      child: Row(
        children: [
          _PhaseStep(
            icon: Icons.play_circle_outline,
            label: 'Idle',
            isActive: isIdle,
            isCompleted: state.scopeActive || state.scopeEnding || state.scopeEnded,
          ),
          _PhaseConnector(isActive: state.scopeActive || isEnding || isEnded),
          _PhaseStep(
            icon: Icons.sync,
            label: 'Scope Active',
            isActive: isActive,
            isCompleted: isEnding || isEnded,
          ),
          _PhaseConnector(isActive: isEnding || isEnded),
          _PhaseStep(
            icon: Icons.cleaning_services,
            label: 'Cleanup',
            isActive: isEnding,
            isCompleted: isEnded,
            highlight: isEnding,
          ),
          _PhaseConnector(isActive: isEnded),
          _PhaseStep(
            icon: Icons.check_circle_outline,
            label: 'Ended',
            isActive: isEnded,
            isCompleted: false,
            highlight: isEnded,
            highlightColor: Colors.blue,
          ),
        ],
      ),
    );
  }
}

class _PhaseStep extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isActive;
  final bool isCompleted;
  final bool highlight;
  final Color? highlightColor;

  const _PhaseStep({
    required this.icon,
    required this.label,
    required this.isActive,
    required this.isCompleted,
    this.highlight = false,
    this.highlightColor,
  });

  @override
  Widget build(BuildContext context) {
    final color = highlight
        ? (highlightColor ?? Colors.orange)
        : isActive
            ? Colors.green
            : isCompleted
                ? Colors.green.shade300
                : Colors.grey.shade400;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: isActive || highlight ? color.withValues(alpha: 0.2) : null,
            shape: BoxShape.circle,
            border: Border.all(color: color, width: 2),
          ),
          child: Icon(icon, size: 20, color: color),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            fontWeight: isActive || highlight ? FontWeight.bold : FontWeight.normal,
            color: color,
          ),
        ),
      ],
    );
  }
}

class _PhaseConnector extends StatelessWidget {
  final bool isActive;

  const _PhaseConnector({required this.isActive});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        height: 2,
        margin: const EdgeInsets.only(bottom: 16),
        color: isActive ? Colors.green : Colors.grey.shade300,
      ),
    );
  }
}

/// Control buttons for the demo.
class _ControlPanel extends StatelessJuiceWidget<LifecycleDemoBloc> {
  _ControlPanel() : super(groups: const {LifecycleDemoGroups.controls});

  @override
  Widget onBuild(BuildContext context, StreamStatus status) {
    final state = bloc.state;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
          bottom: BorderSide(color: Colors.grey.shade200),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: _ActionButton(
                  onPressed: state.scopeActive ? null : () => bloc.send(StartDemoEvent()),
                  icon: Icons.play_arrow,
                  label: 'Start Scope',
                  description: 'Creates FeatureScope, spawns tasks',
                  color: Colors.green,
                  isActive: !state.scopeActive,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _ActionButton(
                  onPressed: state.scopeActive && !state.scopeEnding
                      ? () => bloc.send(EndDemoEvent())
                      : null,
                  icon: state.scopeEnding ? Icons.hourglass_top : Icons.stop,
                  label: state.scopeEnding ? 'Cleaning up...' : 'End Scope',
                  description: state.scopeEnding
                      ? 'CleanupBarrier waiting...'
                      : 'Triggers cleanup barrier',
                  color: Colors.red,
                  isActive: state.scopeActive && !state.scopeEnding,
                  showProgress: state.scopeEnding,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.amber.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.amber.shade200),
            ),
            child: Row(
              children: [
                Switch(
                  value: state.addSlowCleanup,
                  onChanged: state.scopeActive
                      ? null
                      : (_) => bloc.send(ToggleSlowCleanupEvent()),
                  activeTrackColor: Colors.amber.shade200,
                  activeThumbColor: Colors.amber.shade700,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Simulate slow cleanup (5 seconds)',
                        style: TextStyle(
                          fontWeight: FontWeight.w500,
                          color: state.scopeActive ? Colors.grey : Colors.amber.shade900,
                        ),
                      ),
                      Text(
                        'Tests CleanupBarrier timeout behavior',
                        style: TextStyle(
                          fontSize: 12,
                          color: state.scopeActive ? Colors.grey : Colors.amber.shade700,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final IconData icon;
  final String label;
  final String description;
  final Color color;
  final bool isActive;
  final bool showProgress;

  const _ActionButton({
    required this.onPressed,
    required this.icon,
    required this.label,
    required this.description,
    required this.color,
    required this.isActive,
    this.showProgress = false,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: isActive ? color : Colors.grey.shade200,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              if (showProgress)
                SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white.withValues(alpha: 0.8),
                  ),
                )
              else
                Icon(
                  icon,
                  color: isActive ? Colors.white : Colors.grey.shade500,
                  size: 24,
                ),
              const SizedBox(height: 8),
              Text(
                label,
                style: TextStyle(
                  color: isActive ? Colors.white : Colors.grey.shade600,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                description,
                style: TextStyle(
                  color: isActive ? Colors.white.withValues(alpha: 0.8) : Colors.grey.shade500,
                  fontSize: 10,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Task summary showing counts.
class _TaskSummary extends StatelessJuiceWidget<LifecycleDemoBloc> {
  _TaskSummary() : super(groups: const {LifecycleDemoGroups.tasks});

  @override
  Widget onBuild(BuildContext context, StreamStatus status) {
    final tasks = bloc.state.tasks;
    if (tasks.isEmpty) return const SizedBox.shrink();

    final running = tasks.where((t) => t.status == TaskStatus.running).length;
    final completed = tasks.where((t) => t.status == TaskStatus.completed).length;
    final canceled = tasks.where((t) => t.status == TaskStatus.canceled).length;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: Colors.grey.shade50,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _StatChip(
            icon: Icons.play_circle,
            label: 'Running',
            count: running,
            color: Colors.green,
          ),
          _StatChip(
            icon: Icons.check_circle,
            label: 'Completed',
            count: completed,
            color: Colors.blue,
          ),
          _StatChip(
            icon: Icons.cancel,
            label: 'Canceled',
            count: canceled,
            color: Colors.red,
          ),
        ],
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final int count;
  final Color color;

  const _StatChip({
    required this.icon,
    required this.label,
    required this.count,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 4),
        Text(
          '$count $label',
          style: TextStyle(
            fontSize: 12,
            color: color,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

/// Grid of task cards.
class _TaskGrid extends StatelessJuiceWidget<LifecycleDemoBloc> {
  _TaskGrid() : super(groups: const {LifecycleDemoGroups.tasks});

  @override
  Widget onBuild(BuildContext context, StreamStatus status) {
    final tasks = bloc.state.tasks;

    if (tasks.isEmpty) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 48),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.rocket_launch, size: 64, color: Colors.grey.shade300),
            const SizedBox(height: 16),
            Text(
              'Press "Start Scope" to begin',
              style: TextStyle(
                color: Colors.grey.shade500,
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Tasks will appear here as simulated async operations',
              style: TextStyle(
                color: Colors.grey.shade400,
                fontSize: 13,
              ),
            ),
          ],
        ),
      );
    }

    // Use Wrap instead of GridView for scrollable container compatibility
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: tasks.map((task) {
          return SizedBox(
            width: (MediaQuery.of(context).size.width - 32) / 2,
            child: TaskCard(task: task),
          );
        }).toList(),
      ),
    );
  }
}

/// Event log showing lifecycle notifications with colors.
class _EventLog extends StatelessJuiceWidget<LifecycleDemoBloc> {
  _EventLog() : super(groups: const {LifecycleDemoGroups.log});

  @override
  Widget onBuild(BuildContext context, StreamStatus status) {
    final log = bloc.state.eventLog;

    return Container(
      height: 140,
      decoration: BoxDecoration(
        color: Colors.grey.shade900,
        border: Border(
          top: BorderSide(color: Colors.grey.shade700, width: 2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            color: Colors.grey.shade800,
            child: Row(
              children: [
                const Icon(Icons.terminal, size: 14, color: Colors.white70),
                const SizedBox(width: 8),
                const Text(
                  'Lifecycle Events',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                Text(
                  '${log.length} events',
                  style: TextStyle(
                    color: Colors.grey.shade500,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: log.isEmpty
                ? Center(
                    child: Text(
                      'Events will appear here...',
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontStyle: FontStyle.italic,
                        fontSize: 12,
                      ),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(8),
                    itemCount: log.length,
                    itemBuilder: (context, index) {
                      final entry = log[index];
                      return _LogEntry(entry: entry);
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _LogEntry extends StatelessWidget {
  final String entry;

  const _LogEntry({required this.entry});

  @override
  Widget build(BuildContext context) {
    // Determine color based on content
    Color color;
    IconData icon;

    if (entry.contains('started')) {
      color = Colors.greenAccent;
      icon = Icons.play_arrow;
    } else if (entry.contains('ending') || entry.contains('Ending')) {
      color = Colors.orangeAccent;
      icon = Icons.hourglass_top;
    } else if (entry.contains('ended') || entry.contains('Ended')) {
      color = Colors.blueAccent;
      icon = Icons.check;
    } else if (entry.contains('cancel') || entry.contains('Cancel')) {
      color = Colors.redAccent;
      icon = Icons.cancel;
    } else {
      color = Colors.grey.shade400;
      icon = Icons.info_outline;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              entry,
              style: TextStyle(
                color: color,
                fontFamily: 'monospace',
                fontSize: 11,
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
