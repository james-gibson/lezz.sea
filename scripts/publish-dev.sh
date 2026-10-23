#!/bin/bash
#
# publish-dev.sh — build, sign, package and publish a dev build of lezz.sea.
#
# The signature comes from this machine's keychain: the Developer ID Application
# identity (team 288ZTJGXX9) lives here, and only here. CI has no certificate
# and never signs anything. .github/workflows/verify-dev.yml only verifies what
# this script uploads, using scripts/verify-bundle.sh, which needs no
# certificate either.
#
# A publish writes three assets to the rolling `dev` prerelease:
#
#   lezz.sea.app.zip  the signed, hardened-runtime bundle (ditto archive)
#   checksums.txt     sha256 of the zip, in `shasum -c` format
#   dev.json          build identity: version, build, commit, sha, team, notarized
#
# and, when the tree is clean, a tag dev-<build> on the published commit.
# The assets are replaced on every publish, so these URLs are permanently stable:
#
#   https://github.com/james-gibson/lezz.sea/releases/download/dev/lezz.sea.app.zip
#   https://github.com/james-gibson/lezz.sea/releases/download/dev/dev.json
#
# usage: scripts/publish-dev.sh [--dry-run] [--allow-dirty] [--notarize [PROFILE]]
#
#   --dry-run       build, verify and package; print what would be published and
#                   leave the artifacts in build/dev-<build>/
#   --allow-dirty   publish the working tree as it is. No tag (a tag would point
#                   at a commit that is not the build); dev.json says dirty.
#   --notarize      notarize and staple before packaging. The notarytool keychain
#                   profile is the next word if given, else $NOTARY_PROFILE, else
#                   `lezz-sea-notary`. Without this flag the build is signed but
#                   not notarized, and the release notes say so.
#
# Requires: macOS with Xcode, the Developer ID identity in the keychain, `gh`
# authenticated for the repo. Everything is built in build/ (git-ignored).
set -euo pipefail

REPO_ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$REPO_ROOT"

CHANNEL=dev
PROJECT=LezzSea.xcodeproj
SCHEME=LezzSea
EXPORT_OPTIONS=scripts/ExportOptions.plist
EXPECTED_BUNDLE_ID=co.jamesgibson.LezzSea
EXPECTED_TEAM_ID=288ZTJGXX9
EXPECTED_AUTHORITY="Developer ID Application: James Gibson (288ZTJGXX9)"
NOTARY_PROFILE="${NOTARY_PROFILE:-lezz-sea-notary}"

DRY_RUN=0
ALLOW_DIRTY=0
NOTARIZE=0

while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) DRY_RUN=1; shift ;;
    --allow-dirty) ALLOW_DIRTY=1; shift ;;
    --notarize)
      NOTARIZE=1
      shift
      # An optional profile name may follow, as long as it is not another flag.
      if [ $# -gt 0 ] && [ "${1#--}" = "$1" ]; then
        NOTARY_PROFILE="$1"
        shift
      fi
      ;;
    -h|--help)
      sed -n '2,40p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *) echo "unknown argument: $1" >&2; exit 64 ;;
  esac
done

say() { printf '==> %s\n' "$*"; }
warn() { printf 'warning: %s\n' "$*" >&2; }
die() { printf 'error: %s\n' "$*" >&2; exit 1; }

# --- preconditions ----------------------------------------------------------
# Each one is a fact the publish cannot fix later: a missing identity produces
# an ad-hoc signature that looks like success, and a dirty tree produces a build
# nothing can reproduce from a commit.

[ "$(uname -s)" = Darwin ] || die "this publishes a macOS bundle and signs it with a keychain identity; run it on macOS"
command -v xcodebuild >/dev/null 2>&1 || die "xcodebuild not found (install Xcode)"
command -v ditto >/dev/null 2>&1 || die "ditto not found"
command -v gh >/dev/null 2>&1 || die "gh not found"
gh auth status >/dev/null 2>&1 || die "gh is not authenticated"
security find-identity -v -p codesigning 2>/dev/null | grep -F "\"$EXPECTED_AUTHORITY\"" >/dev/null \
  || die "no '$EXPECTED_AUTHORITY' identity in the keychain (security find-identity -v -p codesigning)"
[ -f "$EXPORT_OPTIONS" ] || die "missing $EXPORT_OPTIONS"

DIRTY=false
if [ -n "$(git status --porcelain)" ]; then
  DIRTY=true
  if [ "$ALLOW_DIRTY" -eq 0 ]; then
    git status --short >&2
    die "working tree is dirty; commit it, or pass --allow-dirty (the build will not be tagged)"
  fi
  warn "publishing a dirty tree: no dev-<build> tag, and dev.json records dirty=true"
fi

BUILD=$(date -u +%Y%m%d%H%M%S)
VERSION=$(grep -m1 'MARKETING_VERSION' "$PROJECT/project.pbxproj" | sed -E 's/.*= *([^;]+);/\1/')
COMMIT=$(git rev-parse HEAD)
SHORT=$(git rev-parse --short=12 HEAD)
RELEASE="$VERSION-dev.$BUILD"
WORK="$REPO_ROOT/build/dev-$BUILD"
ARCHIVE="$WORK/lezz.sea.xcarchive"
EXPORT="$WORK/export"
APP="$EXPORT/lezz.sea.app"
ZIP="$WORK/lezz.sea.app.zip"

mkdir -p "$WORK"

# --- build ------------------------------------------------------------------
# Archive + export, not build. `xcodebuild build` signs a development product
# (get-task-allow, no secure timestamp); exporting with method=developer-id
# re-signs for distribution. scripts/verify-bundle.sh enforces the difference.
say "building $RELEASE from $SHORT${DIRTY:+ }"
[ "$DIRTY" = true ] && say "  (dirty tree: $SHORT is not the build)"

if ! xcodebuild archive \
      -project "$PROJECT" \
      -scheme "$SCHEME" \
      -configuration Release \
      -destination 'generic/platform=macOS' \
      -archivePath "$ARCHIVE" \
      -derivedDataPath "$WORK/DerivedData" \
      MARKETING_VERSION="$VERSION" \
      CURRENT_PROJECT_VERSION="$BUILD" \
      >"$WORK/archive.log" 2>&1; then
  tail -40 "$WORK/archive.log" >&2
  die "xcodebuild archive failed (full log: $WORK/archive.log)"
fi

if ! xcodebuild -exportArchive \
      -archivePath "$ARCHIVE" \
      -exportOptionsPlist "$EXPORT_OPTIONS" \
      -exportPath "$EXPORT" \
      >"$WORK/export.log" 2>&1; then
  tail -40 "$WORK/export.log" >&2
  die "xcodebuild -exportArchive failed (full log: $WORK/export.log)"
fi
[ -d "$APP" ] || die "export produced no lezz.sea.app at $APP"

# --- verify the signature before it can be published ------------------------
say "verifying the signature"
scripts/verify-bundle.sh "$APP"

# --- package ----------------------------------------------------------------
# A notarization submission is a zip; the stapled ticket lives in the bundle, so
# we staple and then re-zip. ditto (not zip) preserves the bundle's metadata.
say "packaging"
ditto -c -k --keepParent "$APP" "$ZIP"

if [ "$NOTARIZE" -eq 1 ]; then
  say "notarizing with keychain profile '$NOTARY_PROFILE'"
  if ! xcrun notarytool submit "$ZIP" --keychain-profile "$NOTARY_PROFILE" --wait; then
    die "notarization failed; nothing was published. Store credentials with: xcrun notarytool store-credentials $NOTARY_PROFILE --apple-id <id> --team-id $EXPECTED_TEAM_ID --password <app-specific-password>"
  fi
  xcrun stapler staple "$APP"
  ditto -c -k --keepParent "$APP" "$ZIP"
  say "verifying the notarization ticket"
  scripts/verify-bundle.sh "$APP" --require-notarized
else
  warn "not notarized (pass --notarize once credentials are stored); Gatekeeper needs right-click > Open on first launch"
fi

# --- manifest ---------------------------------------------------------------
# dev.json is the machine-readable record of *what* was published. It is the
# only place a build's commit and signature survive: the release assets are
# replaced on the next publish.
SHA=$(shasum -a 256 "$ZIP" | awk '{print $1}')
SIZE=$(stat -f%z "$ZIP")
CREATED=$(date -u +%Y-%m-%dT%H:%M:%SZ)
NOTARIZED=false
xcrun stapler validate "$APP" >/dev/null 2>&1 && NOTARIZED=true

cat > "$WORK/dev.json" <<JSON
{
  "channel": "$CHANNEL",
  "release": "$RELEASE",
  "version": "$VERSION",
  "build": "$BUILD",
  "commit": "$COMMIT",
  "dirty": $DIRTY,
  "bundleId": "$EXPECTED_BUNDLE_ID",
  "teamId": "$EXPECTED_TEAM_ID",
  "authority": "$EXPECTED_AUTHORITY",
  "hardenedRuntime": true,
  "notarized": $NOTARIZED,
  "sha256": "$SHA",
  "size": $SIZE,
  "createdAt": "$CREATED",
  "asset": "lezz.sea.app.zip"
}
JSON
printf '%s  %s\n' "$SHA" "lezz.sea.app.zip" > "$WORK/checksums.txt"

cat > "$WORK/notes.md" <<NOTES
Dev build **$RELEASE** — commit \`$SHORT\`$( [ "$DIRTY" = true ] && printf ' (dirty tree)' )

| | |
| --- | --- |
| Bundle | \`$EXPECTED_BUNDLE_ID\` |
| Build | \`$BUILD\` |
| Commit | \`$COMMIT\` |
| Signature | $EXPECTED_AUTHORITY |
| Hardened runtime | yes |
| Notarized | $( [ "$NOTARIZED" = true ] && printf 'yes' || printf 'no — right-click > Open on first launch' ) |
| SHA-256 | \`$SHA\` |
| Built | $CREATED |

Download \`lezz.sea.app.zip\`, unzip, and drag **lezz.sea** to /Applications.

These assets are replaced by the next publish, so the download URLs are stable
while the build behind them is not. \`dev.json\` records the commit and checksum
of the build currently published; $( [ "$DIRTY" = true ] && printf 'this one was built from a dirty tree and is not tagged.' || printf "the commit is tagged \`dev-$BUILD\`." )

Verified by .github/workflows/verify-dev.yml on every publish: bundle id,
Developer ID authority, team, hardened runtime, secure timestamp, sha256, and —
when notarized — the stapled ticket.
NOTES

if [ "$DRY_RUN" -eq 1 ]; then
  say "dry run: nothing published"
  printf '  app      %s\n' "$APP"
  printf '  zip      %s (%s bytes)\n' "$ZIP" "$SIZE"
  printf '  manifest %s\n' "$WORK/dev.json"
  printf '  notes    %s\n' "$WORK/notes.md"
  exit 0
fi

# --- publish ----------------------------------------------------------------
say "publishing to the '$CHANNEL' prerelease"
if ! gh release view "$CHANNEL" >/dev/null 2>&1; then
  gh release create "$CHANNEL" --prerelease --title "lezz.sea dev" --notes-file "$WORK/notes.md"
fi
gh release upload "$CHANNEL" "$ZIP" "$WORK/checksums.txt" "$WORK/dev.json" --clobber
gh release edit "$CHANNEL" --notes-file "$WORK/notes.md"

if [ "$DIRTY" = false ]; then
  say "tagging dev-$BUILD"
  git tag "dev-$BUILD" "$COMMIT"
  git push origin "dev-$BUILD"
else
  warn "no tag: a dirty build has no commit to point at"
fi

# Ask CI to verify the asset that is now live. Best effort: the workflow may not
# exist on the default branch yet on the very first publish.
if gh workflow run verify-dev.yml --ref main -f tag="$CHANNEL" >/dev/null 2>&1; then
  say "verification dispatched: gh run list --workflow=verify-dev.yml"
else
  warn "could not dispatch verify-dev.yml (not on main yet?) — verify manually: gh workflow view verify-dev.yml"
fi

say "published $RELEASE"
printf '  zip      https://github.com/$(gh repo view --json nameWithOwner --jq .nameWithOwner)/releases/download/%s/%s\n' "$CHANNEL" "lezz.sea.app.zip"
printf '  manifest https://github.com/$(gh repo view --json nameWithOwner --jq .nameWithOwner)/releases/download/%s/dev.json\n' "$CHANNEL"
