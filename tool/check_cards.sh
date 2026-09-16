#!/usr/bin/env bash
# Check every AI card (packages/<pkg>/doc/LLM.md) against its pubspec.
#
# doc/ai-cards/TEMPLATE.md requires the card's `version` to mirror the
# pubspec and `requires` to mirror the pubspec's dependency constraints.
# Nothing enforced that until 2026-09-15, when nine cards were found adrift
# (ISSUES #23). This is the mechanism: exit 1 on any mismatch.
#
#   tool/check_cards.sh          # all packages
#   tool/check_cards.sh juice_sync   # one package
#
# Constraint mapping (pubspec → card): `^1.6.0` → ">=1.6.0"; an explicit
# range like '>=1.2.0 <3.0.0' → the same string. Every key the card lists
# under `requires` is compared; every juice-family dependency in the pubspec
# must appear in the card. A published package with no card is reported,
# not failed (juice core's guide is AGENTS.md by design).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
exec python3 - "$ROOT" "$@" <<'PY'
import re, sys, glob, os
root, only = sys.argv[1], sys.argv[2:]
fail = 0

def pubspec(pkg):
    s = open(f"{root}/packages/{pkg}/pubspec.yaml").read()
    ver = re.search(r'^version:\s*(\S+)', s, re.M).group(1)
    pub_none = bool(re.search(r'^publish_to:', s, re.M))
    deps = {}
    block = re.search(r'^dependencies:\n((?:  .*\n|\n)*?)(?=^\S)', s, re.M)
    if block:
        for m in re.finditer(r'^  ([a-z0-9_]+):\s*(\S.*)$', block.group(1), re.M):
            deps[m.group(1)] = m.group(2).strip().strip("'\"")
    return ver, pub_none, deps

def card(pkg):
    p = f"{root}/packages/{pkg}/doc/LLM.md"
    if not os.path.exists(p): return None
    s = open(p).read()
    fm = re.match(r'---\n(.*?)\n---', s, re.S)
    if not fm: return {'error': 'no front matter'}
    f = fm.group(1)
    ver = re.search(r'^version:\s*(\S+)', f, re.M)
    req = {}
    rb = re.search(r'^requires:\n((?:  .*\n?)+)', f, re.M)
    if rb:
        for m in re.finditer(r'^  ([a-z0-9_]+):\s*"?([^"\n]+)"?\s*$', rb.group(1), re.M):
            req[m.group(1)] = m.group(2).strip()
    return {'version': ver.group(1) if ver else None, 'requires': req}

def expected(constraint):
    c = constraint.strip()
    m = re.match(r'^\^(\d+\.\d+\.\d+\S*)$', c)
    return f">={m.group(1)}" if m else c

pkgs = sorted(os.path.basename(os.path.dirname(p)) for p in glob.glob(f"{root}/packages/*/pubspec.yaml"))
if only: pkgs = [p for p in pkgs if p in only]
for pkg in pkgs:
    ver, pub_none, deps = pubspec(pkg)
    if pub_none: continue
    c = card(pkg)
    if c is None:
        print(f"  info  {pkg}: no doc/LLM.md" + (" (by design: AGENTS.md)" if pkg == "juice" else ""))
        continue
    if 'error' in c:
        print(f"  FAIL  {pkg}: card {c['error']}"); fail = 1; continue
    if c['version'] != ver:
        print(f"  FAIL  {pkg}: card version {c['version']} != pubspec {ver}"); fail = 1
    for k, v in c['requires'].items():
        if k not in deps:
            print(f"  FAIL  {pkg}: card requires {k} but pubspec has no such dependency"); fail = 1
        elif expected(deps[k]) != v:
            print(f"  FAIL  {pkg}: card requires {k} \"{v}\" != pubspec {deps[k]} (expect \"{expected(deps[k])}\")"); fail = 1
    for k in deps:
        if k.startswith('juice') and k not in c['requires']:
            print(f"  FAIL  {pkg}: pubspec depends on {k} but card requires omits it"); fail = 1
print("cards in sync with pubspecs" if not fail else "card drift — fix doc/LLM.md front matter (see doc/ai-cards/TEMPLATE.md)")
sys.exit(fail)
PY
