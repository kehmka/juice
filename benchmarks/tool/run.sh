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

# Toolchain pin. Timing numbers are only comparable when the Flutter/Dart
# that compiled them is the same; TOOLCHAIN holds the version the published
# results used. A mismatch is an error, not a warning — unless
# JUICE_BENCH_ALLOW_DRIFT=1, in which case the results say so themselves
# ("toolchainDrift": true) and must not be pasted into RESULTS.md.
pinned=$(cat TOOLCHAIN)
have=$(flutter --version 2>/dev/null | awk 'NR==1{print $2}')
drift=false
if [ "$have" != "$pinned" ]; then
  if [ "${JUICE_BENCH_ALLOW_DRIFT:-0}" = "1" ]; then
    echo "WARNING: Flutter $have != pinned $pinned; results will carry toolchainDrift=true" >&2
    drift=true
  else
    echo "ERROR: Flutter $have but TOOLCHAIN pins $pinned. Install the pinned version," >&2
    echo "       or set JUICE_BENCH_ALLOW_DRIFT=1 for a run whose numbers are not publishable." >&2
    exit 1
  fi
fi
defines="--dart-define=BENCH_FLUTTER=$have --dart-define=BENCH_TOOLCHAIN_DRIFT=$drift"

# Linux (the published numbers) runs headless under Xvfb and writes
# results/timing.json + breakdown.json. macOS runs on the real display
# (a window appears for a few seconds per run) and writes the
# *_macos.json files, so a second machine never overwrites the first.
case "$(uname -s)" in
  Darwin)
    platform=macos
    bundle=build/macos/Build/Products/Release/juice_benchmarks.app/Contents/MacOS/juice_benchmarks
    # The frame benchmark needs a VISIBLE window (the engine stops frames for
    # an occluded one — the run sits at 0% CPU until it is fronted). Launch,
    # then keep activating it until the app exits; expect focus to be taken.
    run() {
      "$bundle" & app=$!
      while kill -0 $app 2>/dev/null; do
        osascript -e 'tell application "juice_benchmarks" to activate' >/dev/null 2>&1 || true
        sleep 10
      done
      wait $app
    }
    suffix=_macos ;;
  *)
    platform=linux
    bundle=build/linux/x64/release/bundle/juice_benchmarks
    run() { xvfb-run -a "$bundle"; }
    suffix= ;;
esac

flutter pub get >/dev/null
flutter test --no-pub test/rebuild_counts_test.dart

flutter build "$platform" --release $defines >/dev/null
out=$(run 2>/dev/null)
echo "$out" | sed -n '/BENCH_JSON_BEGIN/,/BENCH_JSON_END/p' \
  | sed '1d;$d' > "results/timing$suffix.json"

flutter build "$platform" --release -t lib/breakdown_main.dart $defines >/dev/null
out=$(run 2>/dev/null)
echo "$out" | sed -n '/BENCH_JSON_BEGIN/,/BENCH_JSON_END/p' \
  | sed '1d;$d' > "results/breakdown$suffix.json"
echo "wrote results/rebuild_counts.json, results/timing$suffix.json and results/breakdown$suffix.json"
