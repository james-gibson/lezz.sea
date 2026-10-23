#!/bin/bash
#
# verify-bundle.sh — prove a built lezz.sea.app carries the distribution
# signature we expect: Developer ID Application (team 288ZTJGXX9), hardened
# runtime, a secure timestamp, and — when asked — a stapled notarization ticket.
#
# Signing is local. This script never signs and needs no certificate, only the
# bundle, so it is safe to run anywhere including CI. The publish script runs it
# before the upload and .github/workflows/verify-dev.yml runs this same file
# after the download: the published asset is judged by the same code on both
# sides, so "it verified here" means "it verifies there".
#
# usage: scripts/verify-bundle.sh <path/to/lezz.sea.app> [--require-notarized]
#
# Environment overrides (for tests, or if the app is ever renamed):
#   EXPECTED_BUNDLE_ID  (default co.jamesgibson.LezzSea)
#   EXPECTED_TEAM_ID    (default 288ZTJGXX9)
#   EXPECTED_AUTHORITY  (default "Developer ID Application: James Gibson (288ZTJGXX9)")
set -euo pipefail

APP=""
REQUIRE_NOTARIZED=0

for arg in "$@"; do
  case "$arg" in
    --require-notarized) REQUIRE_NOTARIZED=1 ;;
    -h|--help)
      sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    -*) echo "unknown flag: $arg" >&2; exit 64 ;;
    *)
      if [ -n "$APP" ]; then
        echo "unexpected extra argument: $arg" >&2
        exit 64
      fi
      APP="$arg"
      ;;
  esac
done

EXPECTED_BUNDLE_ID="${EXPECTED_BUNDLE_ID:-co.jamesgibson.LezzSea}"
EXPECTED_TEAM_ID="${EXPECTED_TEAM_ID:-288ZTJGXX9}"
EXPECTED_AUTHORITY="${EXPECTED_AUTHORITY:-Developer ID Application: James Gibson (288ZTJGXX9)}"

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
note() { printf '  %s\n' "$*" >&2; }

[ -n "$APP" ] || fail "usage: scripts/verify-bundle.sh <path/to/lezz.sea.app> [--require-notarized]"
[ -d "$APP" ] || fail "not a bundle: $APP"
[ -f "$APP/Contents/Info.plist" ] || fail "no Contents/Info.plist in $APP"

# 1. It is the app we think it is.
bundle_id=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Contents/Info.plist" 2>/dev/null || true)
[ "$bundle_id" = "$EXPECTED_BUNDLE_ID" ] \
  || fail "bundle id is '$bundle_id', expected '$EXPECTED_BUNDLE_ID'"
note "bundle id $bundle_id"

# 2. The signature is intact — --deep also covers nested code (frameworks,
#    helpers), --strict enforces resource-rule correctness.
if ! verify_output=$(codesign --verify --deep --strict --verbose=2 "$APP" 2>&1); then
  printf '%s\n' "$verify_output" >&2
  fail "codesign --verify --deep --strict"
fi
note "signature verifies (deep, strict)"

# 3. It is the signature we expect, made the way a distributable app must be.
details=$(codesign -dv --verbose=4 "$APP" 2>&1 || true)
team_id=$(printf '%s\n' "$details" | sed -n 's/^TeamIdentifier=//p')
authority=$(printf '%s\n' "$details" | sed -n 's/^Authority=//p' | head -1)
[ "$team_id" = "$EXPECTED_TEAM_ID" ] \
  || fail "team id is '$team_id', expected '$EXPECTED_TEAM_ID'"
[ "$authority" = "$EXPECTED_AUTHORITY" ] \
  || fail "authority is '$authority', expected '$EXPECTED_AUTHORITY'"
printf '%s\n' "$details" | grep -q '(runtime)' \
  || fail "hardened runtime missing from the signature flags"
# A secure timestamp is what lets the signature outlive the certificate; it is
# also a notarization requirement. An `xcodebuild build` Release product does
# NOT have one — that is why the publish script archives and exports instead.
printf '%s\n' "$details" | grep -q '^Timestamp=' \
  || fail "no secure timestamp (build with archive + exportArchive, not build)"
note "$authority, hardened runtime, secure timestamp"

# 4. Notarization. Optional by default: a signed but un-notarized dev build is
#    publishable, it just needs right-click > Open on first launch.
notarized=no
if xcrun stapler validate "$APP" >/dev/null 2>&1; then
  notarized=yes
  note "notarization ticket stapled"
elif [ "$REQUIRE_NOTARIZED" -eq 1 ]; then
  fail "no stapled notarization ticket (--require-notarized)"
fi

if [ "$notarized" = yes ]; then
  # spctl reports the verdict on stdout and exits 0 either way, so the text is
  # the result: "accepted ... source=Notarized Developer ID".
  assessment=$(spctl --assess --type execute --verbose=2 "$APP" 2>&1 || true)
  printf '%s\n' "$assessment" | grep -q 'accepted' \
    || { printf '%s\n' "$assessment" >&2; fail "Gatekeeper rejects the bundle"; }
  printf '%s\n' "$assessment" | grep -q 'source=Notarized Developer ID' \
    || fail "Gatekeeper source is not 'Notarized Developer ID'"
  note "Gatekeeper accepts it as a Notarized Developer ID app"
fi

printf 'OK %s team=%s notarized=%s\n' "$bundle_id" "$EXPECTED_TEAM_ID" "$notarized"
