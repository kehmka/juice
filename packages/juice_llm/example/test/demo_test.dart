import 'package:flutter_test/flutter_test.dart';
import 'package:juice/juice.dart';
import 'package:juice_llm/juice_llm.dart';

import 'package:juice_llm_example/main.dart';

void main() {
  testWidgets('Echo demo streams a reply to the screen', (tester) async {
    BlocScope.register<LlmBloc>(
      () => LlmBloc.withConfig(LlmConfig(
        provider: EchoLlmProvider(perTokenDelay: const Duration(milliseconds: 1)),
      )),
      lifecycle: BlocLifecycle.permanent,
    );
    BlocScope.get<LlmBloc>().loadModel(LlmModel(
      id: 'echo',
      displayName: 'Echo',
      source: Uri.parse('echo:reference'),
      sha256: '',
      sizeBytes: 0,
    ));

    await tester.pumpWidget(const DemoApp());
    await tester.pump(const Duration(milliseconds: 20));

    // Generate, then let the echo stream finish.
    await tester.tap(find.text('Generate'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    // The echo reply quotes the prompt back — assert some of it rendered.
    expect(find.textContaining('river'), findsWidgets);
  });
}
