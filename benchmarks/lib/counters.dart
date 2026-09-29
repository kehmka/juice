/// Instrumentation shared by every variant: how many times each cell widget
/// BUILT, and how many times a consumer-side selector RAN. Both are plain
/// counters incremented from inside the measured code paths.
class Counters {
  Counters._();

  static List<int> builds = [];
  static int selectorCalls = 0;

  /// The wide scenario's header (a value derived over every cell).
  static int headerBuilds = 0;

  static void reset(int cells) {
    builds = List<int>.filled(cells, 0);
    selectorCalls = 0;
    headerBuilds = 0;
  }

  static int get totalBuilds => builds.fold(0, (a, b) => a + b);
}
