import 'package:juice/juice.dart';
import '../onboard.dart';

/// Handles NextPageEvent to move to the next page
class NextPageUseCase extends UseCase<OnboardingBloc, NextPageEvent> {
  @override
  Future<void> execute(NextPageEvent event) async {
    final newPage = bloc.state.currentPage + 1;
    if (newPage < 3) {
      emitUpdate(
          groupsToRebuild: {"*"},
          newState: bloc.state.copyWith(currentPage: newPage));
    } else {
      // Finish onboarding (Navigate to Home or another screen)
    }
  }
}
