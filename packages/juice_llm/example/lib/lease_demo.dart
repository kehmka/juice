import 'package:juice/juice.dart';
import 'package:juice_llm/juice_llm.dart';

/// THE ENGINE LEASE, demonstrated end to end against the Echo runtime.
///
/// The scenario is the one that motivated the API (0.2.2–0.3.0): an app
/// enriches continuously in a background lane while the user can open a
/// warm, multi-turn conversation at any moment. Native runtimes hold ONE
/// live session per model, so the conversation must own the engine for its
/// whole lifetime — and it must CLAIM the engine safely, because cancelling
/// a generation mid-prefill can wedge a native runtime beyond recovery.
///
/// The demo walks the full pattern:
///  1. a background generation is mid-flight (`well-` lane);
///  2. [LlmBloc.preemptAtSafePoint] frees the engine — cancelling only once
///     tokens stream, never mid-prefill, and only lanes [where] allows;
///  3. [LlmBloc.acquireEngine] takes exclusive ownership; work submitted by
///     anyone else queues behind [EngineLease.release] instead of touching
///     the runtime (this is what keeps a warm session alive between turns);
///  4. release in a `finally` — [EngineLease.release] is idempotent, and an
///     unreleased lease starves every caller in the app.
///
/// Returns a transcript of what happened, one line per step.
Future<String> runLeaseDemo(LlmBloc llm) async {
  final log = StringBuffer();
  void say(String line) => log.writeln('• $line');

  // 1. A background enrichment pass is running — its lane is visible in
  //    the requestId, which is what priority patterns key on.
  final background = llm.beginGeneration(
    const LlmRequest(requestId: 'well-demo', messages: [
      LlmMessage.user('a long unhurried reflection, told slowly enough '
          'that an interactive caller arrives while it is still speaking'),
    ]),
    onChunk: (_) {},
  );
  // Let it truly claim the runtime — the queue admits it on a microtask,
  // and preempting before that would free an engine nobody held yet.
  while (llm.activeRequestId != 'well-demo') {
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  say('background generation "well-demo" is streaming');

  // 2. The user opens a conversation: free the engine at a SAFE point.
  //    Not a blind stopGeneration() — a cancel that lands mid-prefill can
  //    wedge a native runtime (LiteRT). Only background lanes qualify.
  final freed = await llm.preemptAtSafePoint(
    where: (id) => id.startsWith('well-'),
  );
  say('preemptAtSafePoint(where: well-*) → freed=$freed');
  final outcome = await background;
  say('"well-demo" ended ${outcome.kind.name} — a preempted item is left '
      'undone and retried later, never lost');

  // 3. Exclusive ownership for the conversation's lifetime.
  final lease = await llm.acquireEngine();
  say('lease held — llm.engineLeased=${llm.engineLeased}');
  try {
    // A real holder drives the runtime's own session API here — e.g.
    // flutter_gemma's InferenceChat across turns and tool calls, entirely
    // outside beginGeneration. Echo has no session object, so the demo
    // proves the guarantee instead: generations submitted while the lease
    // is held do NOT run until it is released.
    var ranWhileLeased = false;
    final queued = llm.beginGeneration(
      const LlmRequest(requestId: 'chat-after-lease', messages: [
        LlmMessage.user('I run only after the conversation lets go'),
      ]),
      onChunk: (_) => ranWhileLeased = true,
    );
    await Future<void>.delayed(const Duration(milliseconds: 400));
    say('while leased: queued generation produced tokens? '
        '$ranWhileLeased (it is waiting behind release)');

    lease.release();
    say('lease released');
    final queuedOutcome = await queued;
    say('queued generation then ran to ${queuedOutcome.kind.name}');
  } finally {
    lease.release(); // idempotent — the finally is the discipline
  }
  return log.toString();
}
