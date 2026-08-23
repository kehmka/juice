#!/usr/bin/env bash
# Publish juice_observability with a freshly built DevTools extension.
# extension/devtools/build/ is git-ignored (44MB Flutter-web + CanvasKit);
# .pubignore re-includes it in the archive, and this rebuilds it first so
# the published bundle is never stale or empty. Run from the juice repo root.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
EXT="$ROOT/packages/juice_observability_devtools_extension"
PKG="$ROOT/packages/juice_observability"

echo "==> Building the DevTools extension web app"
(cd "$EXT" && flutter pub get && \
  dart run devtools_extensions build_and_copy --source=. --dest="$PKG/extension/devtools")
echo "==> Validating"
(cd "$EXT" && dart run devtools_extensions validate --package="$PKG")
echo "==> Publishing"
(cd "$PKG" && flutter pub publish)
