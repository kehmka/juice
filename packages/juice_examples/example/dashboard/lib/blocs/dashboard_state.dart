import 'package:juice/juice.dart';
import '../models/dashboard_stats.dart';
import '../models/user_activity.dart';

class DashboardState extends BlocState {
  final DashboardStats? stats;
  final List<UserActivity> recentActivity;
  final bool isLoading;

  const DashboardState({
    this.stats,
    this.recentActivity = const [],
    this.isLoading = false,
  });

  DashboardState copyWith({
    DashboardStats? stats,
    List<UserActivity>? recentActivity,
    bool? isLoading,
  }) {
    return DashboardState(
      stats: stats ?? this.stats,
      recentActivity: recentActivity ?? this.recentActivity,
      isLoading: isLoading ?? this.isLoading,
    );
  }
}
