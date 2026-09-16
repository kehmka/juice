#!/usr/bin/env bash
# Sync the AI skill bundle's references from their sources of truth.
#
# The skill at skills/juice/ is DISTRIBUTION of doctrine that lives elsewhere:
# AGENTS.md (the framework guide), llms.txt (the package index), and each
# package's doc/LLM.md (its AI card). This script copies them into
# skills/juice/references/ so the skill is self-contained when installed,
# rewriting only the intra-repo links so they resolve inside the bundle.
# Never edit the copies — edit the source and re-run.
#
#   tool/sync_skill.sh          # refresh the copies
#   tool/sync_skill.sh --check  # exit 1 if any copy is stale (for CI)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REF="$ROOT/skills/juice/references"
MODE="${1:-sync}"

# Link rewrites, applied to every copy:
#   packages/<pkg>/doc/LLM.md            -> packages/<pkg>.md   (the card copies)
#   packages/juice/doc/<DOC>.md          -> juice/<DOC>.md      (core docs copied below)
#   AGENTS.md (bare, as a link target)   -> agents-guide.md
#   ROADMAP.md, doc/ai-cards/TEMPLATE.md  -> GitHub URLs (not bundled)
rewrite() {
  sed -E \
    -e 's#packages/([a-z0-9_]+)/doc/LLM\.md#packages/\1.md#g' \
    -e 's#\]\(doc/ai-cards/TEMPLATE\.md\)#](https://github.com/kehmka/juice/blob/main/doc/ai-cards/TEMPLATE.md)#g' \
    -e 's#packages/juice/doc/([A-Z_]+\.md)#juice/\1#g' \
    -e 's#\]\(AGENTS\.md\)#](agents-guide.md)#g' \
    -e 's#\]\(ROADMAP\.md\)#](https://github.com/kehmka/juice/blob/main/ROADMAP.md)#g'
}

# source -> destination pairs
pairs() {
  echo "$ROOT/AGENTS.md|$REF/agents-guide.md"
  echo "$ROOT/llms.txt|$REF/index.md"
  for d in "$ROOT"/packages/juice/doc/*.md; do
    echo "$d|$REF/juice/$(basename "$d")"
  done
  for card in "$ROOT"/packages/*/doc/LLM.md; do
    pkg="$(basename "$(dirname "$(dirname "$card")")")"
    echo "$card|$REF/packages/$pkg.md"
  done
}

stale=0
while IFS='|' read -r src dst; do
  [ -f "$src" ] || { echo "missing source: $src" >&2; exit 2; }
  if [ "$MODE" = "--check" ]; then
    if [ ! -f "$dst" ] || ! diff -q <(rewrite < "$src") "$dst" >/dev/null; then
      echo "STALE: $dst (source: ${src#$ROOT/})"; stale=1
    fi
  else
    rewrite < "$src" > "$dst"
  fi
done < <(pairs)

if [ "$MODE" = "--check" ]; then
  [ "$stale" = 0 ] && echo "skill references in sync" || { echo "run tool/sync_skill.sh"; exit 1; }
else
  echo "synced: $(pairs | wc -l | tr -d ' ') files into skills/juice/references/"
fi
