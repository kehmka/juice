class UserActivity {
  final String userName;
  final String action;
  final DateTime timestamp;

  const UserActivity({
    required this.userName,
    required this.action,
    required this.timestamp,
  });

  static List<UserActivity> get samples {
    final now = DateTime.now();
    return [
      UserActivity(
        userName: 'Alice Johnson',
        action: 'Created new order #1294',
        timestamp: now.subtract(const Duration(minutes: 5)),
      ),
      UserActivity(
        userName: 'Bob Smith',
        action: 'Updated profile settings',
        timestamp: now.subtract(const Duration(minutes: 12)),
      ),
      UserActivity(
        userName: 'Carol Williams',
        action: 'Completed payment of \$299.00',
        timestamp: now.subtract(const Duration(minutes: 28)),
      ),
      UserActivity(
        userName: 'Dave Brown',
        action: 'Registered as new user',
        timestamp: now.subtract(const Duration(hours: 1)),
      ),
      UserActivity(
        userName: 'Eve Davis',
        action: 'Left a product review',
        timestamp: now.subtract(const Duration(hours: 2)),
      ),
    ];
  }
}
