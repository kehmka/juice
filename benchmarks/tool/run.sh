#!/bin/sh
# Run the full benchmark suite and write results/.
#
#   benchmarks/tool/run.sh
#
# 1. Rebuild counts (deterministic; flutter test) → results/rebuild_counts.json
# 2. Timing (release/AOT Linux build, run headless under Xvfb)
#    → results/timing.json
#
# Needs: Flutter on PATH, the Linux desktop toolchain (clang, cmake, ninja,
# pkg-config, libgtk-3-dev) and xvfb-run. Timing numbers depend on the
# machine — results/timing.json records mode, Dart version and CPU count
# alongside them; compare runs from the same machine only.
set -e
cd "$(dirname "$0")/.."

flutter pub get >/dev/null
flutter test --no-pub test/rebuild_counts_test.dart

flutter build linux --release >/dev/null
bundle=build/linux/x64/release/bundle/juice_benchmarks
out=$(xvfb-run -a "$bundle" 2>/dev/null)
echo "$out" | sed -n '/BENCH_JSON_BEGIN/,/BENCH_JSON_END/p' \
  | sed '1d;$d' > results/timing.json
echo "wrote results/rebuild_counts.json and results/timing.json"
