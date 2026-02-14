import 'package:juice/juice.dart';
import 'package:juice_routing/juice_routing.dart';

class PlaygroundScreen extends StatelessJuiceWidget<RoutingBloc> {
  final int depth;

  PlaygroundScreen({super.key, this.depth = 1});

  @override
  Widget onBuild(BuildContext context, StreamStatus status) {
    final state = bloc.state;

    return Scaffold(
      appBar: AppBar(
        title: Text('Playground #$depth'),
        backgroundColor: _getDepthColor(depth),
        foregroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.home),
          onPressed: () => bloc.resetStack('/'),
          tooltip: 'Reset to Home',
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  'Stack: ${state.stackDepth}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // Action buttons
          Container(
            padding: const EdgeInsets.all(16),
            color: _getDepthColor(depth).withValues(alpha: 0.1),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Navigation Actions',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _ActionButton(
                        label: 'Push',
                        subtitle: 'Add #${depth + 1}',
                        icon: Icons.add,
                        color: Colors.green,
                        onTap: () => bloc.navigate('/playground/${depth + 1}'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _ActionButton(
                        label: 'Replace',
                        subtitle: 'Swap to #${depth + 10}',
                        icon: Icons.swap_horiz,
                        color: Colors.blue,
                        onTap: () => bloc.navigate(
                          '/playground/${depth + 10}',
                          replace: true,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: _ActionButton(
                        label: 'Pop',
                        subtitle: state.canPop ? 'Go back' : 'At root',
                        icon: Icons.remove,
                        color: Colors.orange,
                        onTap: state.canPop ? () => bloc.pop() : null,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _ActionButton(
                        label: 'Pop to Root',
                        subtitle: state.canPop ? 'Clear stack' : 'At root',
                        icon: Icons.first_page,
                        color: Colors.purple,
                        onTap: state.canPop ? () => bloc.popToRoot() : null,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                _ActionButton(
                  label: 'Reset to Home',
                  subtitle: 'Clear everything, go to /',
                  icon: Icons.refresh,
                  color: Colors.red,
                  onTap: () => bloc.resetStack('/'),
                ),
              ],
            ),
          ),

          // Stack visualization
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // Visual stack
                const Text(
                  'Navigation Stack',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                const SizedBox(height: 8),
                ...state.stack.reversed.toList().asMap().entries.map((entry) {
                  final index = state.stack.length - 1 - entry.key;
                  final stackEntry = entry.value;
                  final isTop = index == state.stack.length - 1;
                  final isCurrent = stackEntry.path == '/playground/$depth';

                  return Container(
                    margin: const EdgeInsets.only(bottom: 4),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: isCurrent
                          ? _getDepthColor(depth).withValues(alpha: 0.2)
                          : (isTop ? Colors.grey[200] : Colors.grey[100]),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: isCurrent
                            ? _getDepthColor(depth)
                            : (isTop ? Colors.grey[400]! : Colors.grey[300]!),
                        width: isCurrent ? 2 : 1,
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 24,
                          height: 24,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: isTop ? Colors.grey[700] : Colors.grey[400],
                            shape: BoxShape.circle,
                          ),
                          child: Text(
                            '${index + 1}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            stackEntry.path,
                            style: TextStyle(
                              fontFamily: 'monospace',
                              fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                            ),
                          ),
                        ),
                        if (isTop)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.grey[700],
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text(
                              'TOP',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        if (isCurrent && !isTop) ...[
                          const SizedBox(width: 4),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: _getDepthColor(depth),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text(
                              'YOU',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  );
                }),

                const SizedBox(height: 20),

                // History
                Row(
                  children: [
                    const Text(
                      'History',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                    const Spacer(),
                    Text(
                      '${state.history.length} entries',
                      style: TextStyle(color: Colors.grey[600], fontSize: 12),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                if (state.history.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.grey[100],
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Text(
                      'No history yet. Try the navigation actions above!',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey),
                    ),
                  )
                else
                  ...state.history.reversed.take(10).map((entry) {
                    return Container(
                      margin: const EdgeInsets.only(bottom: 4),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.grey[50],
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: Colors.grey[200]!),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            _getTypeIcon(entry.type),
                            size: 16,
                            color: _getTypeColor(entry.type),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                            decoration: BoxDecoration(
                              color: _getTypeColor(entry.type).withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(3),
                            ),
                            child: Text(
                              entry.type.name.toUpperCase(),
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                                color: _getTypeColor(entry.type),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              entry.path,
                              style: const TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 12,
                              ),
                            ),
                          ),
                          if (entry.timeOnRoute != null)
                            Text(
                              _formatDuration(entry.timeOnRoute!),
                              style: TextStyle(
                                fontSize: 10,
                                color: Colors.grey[500],
                              ),
                            ),
                        ],
                      ),
                    );
                  }),
                if (state.history.length > 10)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      '+ ${state.history.length - 10} more entries',
                      style: TextStyle(color: Colors.grey[500], fontSize: 12),
                      textAlign: TextAlign.center,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Color _getDepthColor(int depth) {
    final colors = [
      Colors.deepPurple,
      Colors.indigo,
      Colors.blue,
      Colors.teal,
      Colors.green,
      Colors.amber,
      Colors.orange,
      Colors.deepOrange,
      Colors.red,
      Colors.pink,
    ];
    return colors[(depth - 1) % colors.length];
  }

  IconData _getTypeIcon(NavigationType type) {
    switch (type) {
      case NavigationType.push:
        return Icons.arrow_forward;
      case NavigationType.pop:
        return Icons.arrow_back;
      case NavigationType.replace:
        return Icons.swap_horiz;
      case NavigationType.reset:
        return Icons.refresh;
    }
  }

  Color _getTypeColor(NavigationType type) {
    switch (type) {
      case NavigationType.push:
        return Colors.green;
      case NavigationType.pop:
        return Colors.orange;
      case NavigationType.replace:
        return Colors.blue;
      case NavigationType.reset:
        return Colors.red;
    }
  }

  String _formatDuration(Duration duration) {
    if (duration.inSeconds < 1) {
      return '${duration.inMilliseconds}ms';
    } else if (duration.inMinutes < 1) {
      return '${duration.inSeconds}s';
    } else {
      return '${duration.inMinutes}m ${duration.inSeconds % 60}s';
    }
  }
}

class _ActionButton extends StatelessWidget {
  final String label;
  final String subtitle;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;

  const _ActionButton({
    required this.label,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isEnabled = onTap != null;

    return Material(
      color: isEnabled ? color : Colors.grey[300],
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Icon(icon, color: Colors.white, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.8),
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
