import 'package:juice/juice.dart';

/// Events for OnboardingBloc
abstract class OnboardingEvent extends EventBase {}

/// Navigate to the next page
class NextPageEvent extends OnboardingEvent {}
