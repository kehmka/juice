import 'package:flutter/widgets.dart';

/// One way of wiring the cells scenario: [cells] widgets, each showing one
/// int of shared state; [update] sets one cell. Every framework gets the same
/// scenario, in its idiomatic ("tuned") and its default ("naive") form.
abstract class Variant {
  /// e.g. `juice · groups`.
  String get name;

  /// `juice`, `bloc` or `riverpod`.
  String get framework;

  /// How this variant targets the rebuild, in one phrase.
  String get mechanism;

  /// Creates fresh state for [cells] cells. Called before [build].
  void setUp(int cells);

  /// The widget tree: [cells] cell widgets in a Wrap (no overflow checks;
  /// every cell is built — no virtualization).
  Widget build(int cells);

  /// Sets cell [index] to [value] and completes when the new state is
  /// observable (the frame that shows it is the caller's business).
  Future<void> update(int index, int value);

  Future<void> tearDown();
}

/// A cell's text; every variant renders exactly this.
Widget cellText(int value) => Text('$value', textDirection: TextDirection.ltr);
