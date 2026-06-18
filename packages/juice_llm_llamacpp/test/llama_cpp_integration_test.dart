import 'dart:io';
import 'dart:typed_data';

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
        provider: LlamaCppProvider(
          libraryPath: libPath,
          // Gemma's embedded template is unparseable — build the prompt here.
          chatFormat:
              modelPath.toLowerCase().contains('gemma') ? gemmaChatFormat : null,
        ),
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

  // --- Multimodal (vision) ---
  // Needs a vision-capable model (Gemma 4) + its mmproj projector + an image.
  final mmprojPath = Platform.environment['LLAMA_MMPROJ'] ??
      '/tmp/llama_spike/models/mmproj-gemma4-e2b-F16.gguf';
  final imagePath = Platform.environment['LLAMA_IMAGE'] ??
      '/Library/Desktop Pictures/Flower 1.jpg';
  final visionAvailable = available &&
      File(mmprojPath).existsSync() &&
      File(imagePath).existsSync() &&
      modelPath.toLowerCase().contains('gemma');

  LlmBloc buildVision() => LlmBloc.withConfig(LlmConfig(
        provider: LlamaCppProvider(
          libraryPath: libPath,
          chatFormat: gemmaChatFormat,
        ),
        resolvePath: (_) => modelPath,
        loadOptions: LlmLoadOptions(
          gpuLayers: 99,
          contextTokens: 4096,
          projectorPath: mmprojPath,
        ),
      ));

  group('LlamaCppProvider multimodal (real model + projector)', () {
    test('describes an image, and advertises vision once the projector loads',
        () async {
      final bloc = buildVision();
      await settle();
      await ready(bloc);

      // Capability is honest: vision/audio appear only after the projector
      // actually loaded.
      expect(bloc.provider.capabilities, contains(LlmCapability.vision));
      expect(bloc.provider.capabilities, contains(LlmCapability.audio));

      final image = Uint8List.fromList(File(imagePath).readAsBytesSync());
      bloc.generate(LlmRequest(
        requestId: 'img',
        messages: [
          LlmMessage.user(
            'Describe this image in one factual sentence.',
            images: [image],
          ),
        ],
        params: const LlmSamplingParams(temperature: 0.3, maxTokens: 64),
      ));
      for (var i = 0; i < 300; i++) {
        final s = bloc.state.sessions['img'];
        if (s != null && s.isTerminal) break;
        await settle(100);
      }
      final s = bloc.state.sessions['img']!;
      expect(s.status, SessionStatus.done);
      expect(s.text.trim(), isNotEmpty,
          reason: 'the model should describe the image');

      await bloc.close();
    }, timeout: const Timeout(Duration(minutes: 3)));

    test('media without a projector fails loud', () async {
      // Load text-only (no projectorPath), then send an image → must throw.
      final bloc = LlmBloc.withConfig(LlmConfig(
        provider:
            LlamaCppProvider(libraryPath: libPath, chatFormat: gemmaChatFormat),
        resolvePath: (_) => modelPath,
      ));
      await settle();
      await ready(bloc);
      expect(
          bloc.provider.capabilities, isNot(contains(LlmCapability.vision)));

      final image = Uint8List.fromList(File(imagePath).readAsBytesSync());
      var threw = false;
      try {
        await bloc.provider.generate(LlmRequest(
          requestId: 'nomm',
          messages: [LlmMessage.user('What is this?', images: [image])],
        )).toList();
      } on LlmProviderException {
        threw = true;
      }
      expect(threw, isTrue, reason: 'media with no projector must fail loud');

      await bloc.close();
    }, timeout: const Timeout(Duration(minutes: 3)));
  },
      skip: visionAvailable
          ? false
          : 'vision needs a Gemma GGUF + LLAMA_MMPROJ + LLAMA_IMAGE');
}
