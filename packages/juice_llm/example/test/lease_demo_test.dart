import 'package:flutter_test/flutter_test.dart';
import 'package:juice_llm/juice_llm.dart';
import 'package:juice_llm_example/lease_demo.dart';

/// The README points at the lease demo as the living walkthrough of the
/// engine-lease pattern — so its transcript must be TRUE, not aspirational.
/// This runs the demo against the real bloc + Echo runtime and asserts each
/// claim it prints.
void main() {
  test('runLeaseDemo transcript matches real engine behavior', () async {
    final llm = LlmBloc.withConfig(LlmConfig(
      provider: EchoLlmProvider(perTokenDelay: const Duration(milliseconds: 40)),
    ));
    llm.loadModel(LlmModel(
      id: 'echo',
      displayName: 'Echo',
      source: Uri.parse('echo:reference'),
      sha256: '',
      sizeBytes: 0,
      capabilities: const {LlmCapability.text},
    ));
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(llm.state.isReady, isTrue, reason: 'echo model should be ready');

    final transcript = await runLeaseDemo(llm);

    // The background lane was preempted at a safe point, not abandoned.
    expect(transcript, contains('freed=true'));
    expect(transcript, contains('ended cancelled'));
    // The lease was visibly held…
    expect(transcript, contains('llm.engineLeased=true'));
    // …and the generation submitted while leased did NOT run until release.
    expect(transcript, contains('produced tokens? false'));
    expect(transcript, contains('then ran to done'));
    // Nothing left leased behind.
    expect(llm.engineLeased, isFalse);

    await llm.close();
  });
}
