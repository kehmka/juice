class DashboardStats {
  final int totalUsers;
  final double revenue;
  final int orders;
  final double conversionRate;

  const DashboardStats({
    this.totalUsers = 0,
    this.revenue = 0,
    this.orders = 0,
    this.conversionRate = 0,
  });

  static const sample = DashboardStats(
    totalUsers: 2847,
    revenue: 48253.90,
    orders: 1293,
    conversionRate: 3.2,
  );
}
