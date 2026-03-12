class ChartData {
  final String label;
  final double value;

  const ChartData({required this.label, required this.value});

  static const weeklyRevenue = [
    ChartData(label: 'Mon', value: 4200),
    ChartData(label: 'Tue', value: 3800),
    ChartData(label: 'Wed', value: 5100),
    ChartData(label: 'Thu', value: 4600),
    ChartData(label: 'Fri', value: 6200),
    ChartData(label: 'Sat', value: 7400),
    ChartData(label: 'Sun', value: 5800),
  ];

  static const monthlyUsers = [
    ChartData(label: 'Jan', value: 180),
    ChartData(label: 'Feb', value: 220),
    ChartData(label: 'Mar', value: 310),
    ChartData(label: 'Apr', value: 290),
    ChartData(label: 'May', value: 420),
    ChartData(label: 'Jun', value: 380),
  ];
}
