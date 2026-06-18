import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:juice_llm/juice_llm.dart';
import 'package:juice_llm_llamacpp/juice_llm_llamacpp.dart';

/// Real-model integration test — runs only when the native lib + a GGUF are
/// present locally (never in CI). Drives the actual `LlmBloc` through the
/// `LlamaCppProvider` against llama.cpp on Metal.
///
/// Provide paths via env, or it falls back to the spike locations:
///   LLAMA_LIB=/path/to/libllama.dylib LLAMA_MODEL=/path/to/model.gguf
void main() {
  final libPath = Platform.environment['LLAMA_LIB'] ??
      '/tmp/llama_spike/libllama/macos/libllama.dylib';
  final modelPath = Platform.environment['LLAMA_MODEL'] ??
      '/tmp/llama_spike/models/SmolLM2-360M-Instruct-Q4_K_M.gguf';

  final available =
      File(libPath).existsSync() && File(modelPath).existsSync();

  LlmModel model() => LlmModel(
        id: 'spike',
        displayName: 'Spike',
        source: Uri.parse('file:$modelPath'),
        sha256: '',
        sizeBytes: 0,
        capabilities: const {LlmCapability.text},
      );

  LlmBloc build() => LlmBloc.withConfig(LlmConfig(
        provider: LlamaCppProvider(libraryPath: libPath),
        resolvePath: (_) => modelPath,
      ));

  Future<void> settle([int ms = 50]) =>
      Future<void>.delayed(Duration(milliseconds: ms));

  Future<void> ready(LlmBloc bloc) async {
    bloc.loadModel(model());
    for (var i = 0; i < 100 && !bloc.state.isReady; i++) {
      await settle(100);
    }
    expect(bloc.state.isReady, isTrue, reason: 'model should load to ready');
  }

  group('LlamaCppProvider + LlmBloc (real model)', () {
    test('streams a real reflection, twice in a row (KV reuse holds)', () async {
      final bloc = build();
      await settle();
      await ready(bloc);

      Future<GenerationSession> run(String id) async {
        bloc.generate(LlmRequest(
          requestId: id,
          messages: const [
            LlmMessage.system('You are the Almanac. Reply in one short sentence.'),
            LlmMessage.user('Name one thing to glean from a quiet morning.'),
          ],
          params: const LlmSamplingParams(temperature: 0.7, maxTokens: 48),
        ));
        for (var i = 0; i < 200; i++) {
          final s = bloc.state.sessions[id];
          if (s != null && s.isTerminal) return s;
          await settle(100);
        }
        return bloc.state.sessions[id]!;
      }

      final s1 = await run('r1');
      expect(s1.status, SessionStatus.done);
      expect(s1.text.trim(), isNotEmpty);

      // Second generation on the same loaded engine — the per-request
      // clearHistory + worker KV clear must avoid a position conflict.
      final s2 = await run('r2');
      expect(s2.status, SessionStatus.done);
      expect(s2.text.trim(), isNotEmpty);

      await bloc.close();
    }, timeout: const Timeout(Duration(minutes: 3)));

    test('cancel marks the session cancelled', () async {
      final bloc = build();
      await settle();
      await ready(bloc);

      bloc.generate(const LlmRequest(
        requestId: 'long',
        messages: [LlmMessage.user('Write a very long essay about the sea.')],
        params: LlmSamplingParams(maxTokens: 800),
      ));
      // let it start streaming
      for (var i = 0; i < 50; i++) {
        final s = bloc.state.sessions['long'];
        if (s != null && s.text.isNotEmpty) break;
        await settle(50);
      }
      bloc.cancel('long');
      // Wait for the session to reach a terminal state (the finalize lands a
      // tick after isGenerating flips false).
      for (var i = 0; i < 100; i++) {
        if (bloc.state.sessions['long']?.isTerminal ?? false) break;
        await settle(50);
      }
      expect(bloc.state.sessions['long']!.status, SessionStatus.cancelled);

      await bloc.close();
    }, timeout: const Timeout(Duration(minutes: 3)));
  }, skip: available ? false : 'native lib + GGUF not present (set LLAMA_LIB / LLAMA_MODEL)');
}
