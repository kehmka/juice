#!/bin/sh
# Coverage gate for packages/juice (core). Run from the repo root:
#
#   tool/coverage_check.sh 80     # fail if core line coverage < 80%
#
# Runs the core suite with --coverage, then sums lcov line hits over lib/,
# EXCLUDING the files listed below. Prints the total and the ten
# least-covered files so a drop is actionable.
#
# Exclusions are explicit and each has a reason — adding one is a review
# decision, not a way to make the number go up:
#   - src/bloc/src/bloc.dart, emitter.dart, bloc_support.dart and
#     global_bloc_resolver.dart: a vendored copy of the `bloc` library's
#     Bloc<Event, State> base and helpers. Exported, but nothing in the
#     family uses them (JuiceBloc does not extend them). Deprecate or remove
#     in 2.0.0; until then they are not Juice's behavior to test.
#   - src/bloc/src/bloc_base.dart: the same vendored base (BlocBase); the
#     interfaces JuiceBloc implements there carry no executable lines.
set -e

threshold="${1:?usage: tool/coverage_check.sh <min-percent>}"
root=$(cd "$(dirname "$0")/.." && pwd)
cd "$root/packages/juice"

flutter test --no-pub --coverage >/dev/null

awk -v min="$threshold" '
  BEGIN {
    ex["lib/src/bloc/src/bloc.dart"] = 1
    ex["lib/src/bloc/src/emitter.dart"] = 1
    ex["lib/src/bloc/src/bloc_support.dart"] = 1
    ex["lib/src/bloc/src/global_bloc_resolver.dart"] = 1
    ex["lib/src/bloc/src/bloc_base.dart"] = 1
  }
  /^SF:/ {
    file = substr($0, 4); sub(/^.*\/lib\//, "lib/", file)
    skip = (file in ex); next
  }
  /^DA:/ && !skip {
    split(substr($0, 4), a, ",")
    total[file]++; if (a[2] > 0) hit[file]++
    T++; if (a[2] > 0) H++
  }
  END {
    if (T == 0) { print "no coverage data"; exit 2 }
    pct = 100 * H / T
    printf "juice core line coverage: %d/%d = %.1f%% (gate: %s%%)\n", H, T, pct, min
    n = 0
    for (f in total) { r[f] = hit[f] / total[f]; names[++n] = f }
    for (i = 1; i <= n; i++) for (j = i + 1; j <= n; j++)
      if (r[names[j]] < r[names[i]]) { t = names[i]; names[i] = names[j]; names[j] = t }
    print "least covered:"
    for (i = 1; i <= n && i <= 10; i++)
      printf "  %5.1f%%  %s\n", 100 * r[names[i]], names[i]
    if (pct + 0.0001 < min) { printf "FAIL: below %s%%\n", min; exit 1 }
  }' coverage/lcov.info
