#!/bin/bash
#
# isotope-tests.sh — run LezzSea's live isotope tests against the KB cluster.
#
# LezzSea is the observation layer; the KB cluster and its scopes are the
# subject. The scans are the executable half of the isotope tests:
#
#   verify-empty (gate, proxy)
#   verify-security (empty facade, keys, negotiation, rotation, honeypot, event)
#   verify-rotations (inverse proxy rotation)
#   negotiate (per-scope isotope receipt)
#
# The KB launcher emits the stable `lezzsea.isotope-tests/v1` manifest. This
# wrapper runs it, validates the manifest, and leaves it in build/ for the app,
# CI, or a release note.
#
# usage: scripts/isotope-tests.sh [--kb-cluster PATH] [--output PATH]
#        scripts/isotope-tests.sh --manifest PATH
#
#   --kb-cluster PATH  launcher (default $KB_CLUSTER, else
#                      ~/projects/kb/scripts/cluster/kb-cluster.sh)
#   --output PATH      manifest destination (default build/isotope-tests.json)
#   --manifest PATH    validate an existing manifest; do not run the scans
#
# The scans need the same user, the same HOME and a running local KB fleet.
# They do not run in the sandboxed app; use the CLI or the Lab build.
set -euo pipefail

REPO_ROOT=$(cd "$(dirname "$0")/.." && pwd)
KB_CLUSTER="${KB_CLUSTER:-$HOME/projects/kb/scripts/cluster/kb-cluster.sh}"
OUTPUT="$REPO_ROOT/build/isotope-tests.json"
MANIFEST=""
RUN=1

usage() {
  sed -n '2,40p' "$0" | sed 's/^# \{0,1\}//'
}

die() { printf 'error: %s\n' "$*" >&2; exit 1; }

while [ $# -gt 0 ]; do
  case "$1" in
    --kb-cluster) KB_CLUSTER="${2:?--kb-cluster needs a path}"; shift 2 ;;
    --output)     OUTPUT="${2:?--output needs a path}"; shift 2 ;;
    --manifest)   MANIFEST="${2:?--manifest needs a path}"; RUN=0; shift 2 ;;
    -h|--help)    usage; exit 0 ;;
    *)            die "unknown argument: $1" ;;
  esac
done

if [ "$RUN" = 1 ]; then
  [ -x "$KB_CLUSTER" ] || die "KB launcher not found or not executable: $KB_CLUSTER"
  mkdir -p "$(dirname "$OUTPUT")"
  rc=0
  "$KB_CLUSTER" isotope-tests --json --output "$OUTPUT" || rc=$?
  [ -f "$OUTPUT" ] || die "no manifest was written to $OUTPUT"
  [ "$rc" -eq 0 ] || printf 'note: launcher exited %s; validating the manifest\n' "$rc" >&2
else
  OUTPUT="$MANIFEST"
  [ -f "$OUTPUT" ] || die "manifest not found: $OUTPUT"
fi

python3 - "$OUTPUT" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
try:
    data = json.loads(path.read_text())
except Exception as exc:
    print("FAIL: manifest is not JSON: %s" % exc, file=sys.stderr)
    raise SystemExit(2)

if data.get("schema") != "lezzsea.isotope-tests/v1":
    print("FAIL: schema is %r, want lezzsea.isotope-tests/v1" % data.get("schema"), file=sys.stderr)
    raise SystemExit(2)

tests = data.get("tests") or []
behavior = data.get("behavior") or {}
failed = [test for test in tests if not test.get("clean")]
failed_behavior = [
    name
    for name, value in behavior.items()
    if isinstance(value, dict) and name != "negotiate" and not value.get("ok")
]
negotiate = behavior.get("negotiate") or {}
failed_negotiate = [name for name, value in negotiate.items() if not value.get("ok")]

print("schema: %s" % data["schema"])
print("subject: %s" % data.get("subject"))
print("canon: %d/%d clean" % (len(tests) - len(failed), len(tests)))
print("behavior: %s" % ", ".join(sorted(k for k in behavior if k != "negotiate")))
print("negotiate: %d/%d" % (len(negotiate) - len(failed_negotiate), len(negotiate)))
print("manifest: %s" % path)
for test in failed:
    print("  FAIL %s (%s)" % (test.get("name"), test.get("isotope")))
for name in failed_behavior:
    print("  FAIL %s" % name)
for name in failed_negotiate:
    print("  FAIL negotiate %s" % name)

if data.get("ok") is not True or failed or failed_behavior or failed_negotiate:
    raise SystemExit(2)
print("ok")
PY
