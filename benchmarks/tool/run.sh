#!/bin/sh
# Run the full benchmark suite and write results/.
#
#   benchmarks/tool/run.sh
#
# 1. Rebuild counts (deterministic; flutter test) → results/rebuild_counts.json
# 2. Timing (release/AOT Linux build, run headless under Xvfb)
#    → results/timing.json
# 3. Dispatch breakdown (same build setup) → results/breakdown.json
#
# Needs: Flutter on PATH, the Linux desktop toolchain (clang, cmake, ninja,
# pkg-config, libgtk-3-dev) and xvfb-run. Timing numbers depend on the
# machine — results/timing.json records mode, Dart version and CPU count
# alongside them; compare runs from the same machine only.
set -e
cd "$(dirname "$0")/.."

# Linux (the published numbers) runs headless under Xvfb and writes
# results/timing.json + breakdown.json. macOS runs on the real display
# (a window appears for a few seconds per run) and writes the
# *_macos.json files, so a second machine never overwrites the first.
case "$(uname -s)" in
  Darwin)
    platform=macos
    bundle=build/macos/Build/Products/Release/juice_benchmarks.app/Contents/MacOS/juice_benchmarks
    run() { "$bundle"; }
    suffix=_macos ;;
  *)
    platform=linux
    bundle=build/linux/x64/release/bundle/juice_benchmarks
    run() { xvfb-run -a "$bundle"; }
    suffix= ;;
esac

flutter pub get >/dev/null
flutter test --no-pub test/rebuild_counts_test.dart

flutter build "$platform" --release >/dev/null
out=$(run 2>/dev/null)
echo "$out" | sed -n '/BENCH_JSON_BEGIN/,/BENCH_JSON_END/p' \
  | sed '1d;$d' > "results/timing$suffix.json"

flutter build "$platform" --release -t lib/breakdown_main.dart >/dev/null
out=$(run 2>/dev/null)
echo "$out" | sed -n '/BENCH_JSON_BEGIN/,/BENCH_JSON_END/p' \
  | sed '1d;$d' > "results/breakdown$suffix.json"
echo "wrote results/rebuild_counts.json, results/timing$suffix.json and results/breakdown$suffix.json"
