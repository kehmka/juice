import 'package:juice/juice.dart';
import 'form.dart';
import 'use_cases/submit_form_use_case.dart';

class FormBloc extends JuiceBloc<ExampleFormState> {
  FormBloc()
      : super(
          ExampleFormState(),
          [
            () => UseCaseBuilder(
                  typeOfEvent: SubmitFormEvent,
                  useCaseGenerator: () => SubmitFormUseCase(),
                ),
          ],
          [],
        );
}
