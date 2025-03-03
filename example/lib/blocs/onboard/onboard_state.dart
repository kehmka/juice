import 'package:juice/juice.dart';

/// States for OnboardingBloc
class OnboardingState extends BlocState {
  final int currentPage;

  const OnboardingState({required this.currentPage});

  OnboardingState copyWith({int? currentPage}) {
    return OnboardingState(
      currentPage: currentPage ?? this.currentPage,
    );
  }
}
