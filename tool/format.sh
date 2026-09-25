#!/bin/sh
# Format (or check) the current package's lib/, test/ and example/ dirs.
# Run per package by `melos run format` / `melos run format:check`.
#
#   tool/format.sh          # rewrite in place
#   tool/format.sh --check  # exit 1 if anything is unformatted; writes nothing
#
# A script, not an inline melos command: melos exec re-evaluates its command
# through /bin/sh, which strips the quotes around an inline `bash -c '...'`,
# so the old bash-array one-liner was a syntax error wherever /bin/sh is dash
# (Ubuntu, i.e. CI) — the format gate had never actually run there.
set -e

if [ "$1" = "--check" ]; then
  set -- --output=none --set-exit-if-changed
else
  set --
fi

found=
for dir in lib test example; do
  # An example/ with its own pubspec is a melos package in its own right and
  # is formatted by its own run. Formatting it here too made two concurrent
  # melos jobs write the same files — and truncated one.
  if [ "$dir" = example ] && [ -f example/pubspec.yaml ]; then
    continue
  fi
  if [ -d "$dir" ]; then
    set -- "$@" "$dir"
    found=1
  fi
done
[ -n "$found" ] || exit 0

exec dart format "$@"
