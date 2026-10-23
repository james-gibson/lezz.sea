# Publishing a dev build

lezz.sea is distributed from this repo's **`dev`** prerelease. The bundle is
signed on the maintainer's machine — the Developer ID certificate is in the
local keychain, never in CI — and a cert-free CI workflow verifies what was
published. One command does a publish:

```sh
scripts/publish-dev.sh
```

That builds, signs, verifies, packages and uploads. Stable download URLs, which
are the same after every publish:

```
https://github.com/james-gibson/lezz.sea/releases/download/dev/lezz.sea.app.zip
https://github.com/james-gibson/lezz.sea/releases/download/dev/dev.json
```

## What a publish produces

| asset | what it is |
| --- | --- |
| `lezz.sea.app.zip` | the signed bundle, archived with `ditto` so bundle metadata survives |
| `checksums.txt` | sha256 of the zip, in `shasum -c` format |
| `dev.json` | build identity: release, build, commit, commit dirtiness, team, authority, notarized, sha256, size, time |

and, from a clean tree, a lightweight tag `dev-<build>` on the published commit.
`dev.json` is the machine-readable record of what is live right now, because the
assets themselves are replaced on the next publish.

## Why the build is an archive + export

`xcodebuild build -configuration Release` is not what gets shipped. It signs
with the Developer ID identity but produces a *development* product:

- it carries `com.apple.security.get-task-allow` (lets a debugger attach), and
- it has **no secure timestamp**.

Both are notarization blockers, and neither is visible from a successful build —
`codesign -dv` just shows a valid signature. `scripts/publish-dev.sh` therefore
runs `xcodebuild archive` and then `-exportArchive` with
`scripts/ExportOptions.plist` (`method = developer-id`), which re-signs for
distribution: hardened runtime, secure timestamp, no `get-task-allow`.

`scripts/verify-bundle.sh` is the check that keeps this honest. It fails a
bundle that lacks a secure timestamp, hardened runtime, the expected authority
or team, or (when asked) a stapled ticket.

## Signing, and what CI can and cannot prove

Signing needs the private key; verification needs only the bundle. That split is
why nothing sensitive is in CI:

| | where |
| --- | --- |
| build + sign + notarize | your machine (`scripts/publish-dev.sh`) |
| verify the published asset | `.github/workflows/verify-dev.yml` on `macos-15`, no certificates |

The workflow downloads the live `dev` assets and checks the checksum, bundle id,
Developer ID authority, team `288ZTJGXX9`, hardened runtime, secure timestamp,
and — when `dev.json` says `notarized: true` — the stapled ticket and Gatekeeper
assessment. It also cross-checks every field of `dev.json` against the unpacked
bundle, so a manifest that disagrees with the zip fails CI.

CI cannot prove *who* ran the build; it proves the published bytes are signed by
this team and match the manifest. The `dev-<build>` tag ties the build to a
commit.

## Notarization

Signing alone leaves Gatekeeper warning on first launch. Notarization needs App
Store Connect credentials, stored once in the login keychain:

```sh
xcrun notarytool store-credentials lezz-sea-notary \
  --apple-id '<your Apple ID>' \
  --team-id 288ZTJGXX9 \
  --password '<app-specific password>'
```

Then publish with notarization:

```sh
scripts/publish-dev.sh --notarize            # profile: lezz-sea-notary
scripts/publish-dev.sh --notarize my-profile # or a profile of your choosing
```

Without the flag the build is signed but not notarized, `dev.json` records
`notarized: false`, and the release notes say to right-click → Open. Nothing
else about the flow changes, so notarization can be turned on later.

## Options

```sh
scripts/publish-dev.sh --dry-run      # build + verify + package, publish nothing
scripts/publish-dev.sh --allow-dirty  # publish the working tree; no tag, dev.json says dirty
```

A dirty tree is refused by default: a published build that no commit can
reproduce is worse than a failed command.

## The channel is rolling, deliberately

`dev` is one prerelease whose assets are replaced on each publish
(`gh release upload --clobber`). That is what makes the URLs stable: a
downloader never has to discover a new tag.

The trade-off is that only the newest build is downloadable. If you need to keep
builds, or if this repo ever enables GitHub's immutable releases, switch the
script to per-build releases (`dev-<build>` with assets) and keep `dev.json` as
the pointer to the newest one.

## Checking a published build by hand

```sh
gh release download dev --pattern 'lezz.sea.app.zip' --pattern 'checksums.txt' --pattern 'dev.json'
shasum -a 256 -c checksums.txt
ditto -x -k lezz.sea.app.zip .
scripts/verify-bundle.sh lezz.sea.app
```

`verify-bundle.sh` exits non-zero and names the failed fact; it prints
`OK <bundle-id> team=<team> notarized=<yes|no>` when everything holds.
