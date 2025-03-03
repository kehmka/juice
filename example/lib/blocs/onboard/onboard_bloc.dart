import 'package:juice/juice.dart';
import 'onboard.dart';

class OnboardingBloc extends JuiceBloc<OnboardingState> {
  OnboardingBloc()
      : super(
          OnboardingState(currentPage: 0),
          [
            () => UseCaseBuilder(
                  typeOfEvent: NextPageEvent,
                  useCaseGenerator: () => NextPageUseCase(),
                ),
          ],
          [],
        );
}
