# App Store review checklist

What the project carries in-repo, and what can only be done in App Store
Connect. The first list is verifiable from a clean checkout; the second is a
record of the manual steps so a submission is not blocked on discovery.

## Carried in the repository

| Requirement | Where |
| --- | --- |
| App Sandbox enabled | `LezzSea/LezzSea.entitlements`, `ENABLE_APP_SANDBOX = YES` |
| Outbound network (adhd, registry, Bonjour) | `com.apple.security.network.client` |
| Read the traffic log | `com.apple.security.files.user-selected.read-only` + security-scoped bookmark in `AppModel.setLogURL` |
| Local network purpose string | `NSLocalNetworkUsageDescription` in `Info.plist` |
| Bonjour service declaration | `NSBonjourServices` (`_adhd-isotope._tcp`) |
| Privacy manifest | `LezzSea/PrivacyInfo.xcprivacy` — UserDefaults, reason `CA92.1`; no tracking, no collected data |
| Export compliance | `ITSAppUsesNonExemptEncryption = false` |
| ATS for loopback / LAN | `NSAllowsLocalNetworking` |
| App category | `LSApplicationCategoryType` = Developer Tools |
| Complete icon set | `Assets.xcassets/AppIcon.appiconset` (16–1024 @1x/@2x) |
| No third-party code | no Swift packages, no frameworks |
| Accessibility | see the Accessibility section of `README.md`; audited shapes, labels, announcements, Reduce Motion, window floor, adaptive table |
| UI tests for the layout floor | `LezzSeaUITests` |
| Sandbox entitlements in the signed bundle | verified with `codesign -d --entitlements :-` |

`xcodebuild test` runs the unit and UI tests; `scripts/verify-bundle.sh` checks
the Developer ID signature, hardened runtime, and stapling for the direct
distribution channel.

## Only in App Store Connect

- [ ] Create the macOS app record with bundle id `co.jamesgibson.LezzSea`.
- [ ] Sign with an **Apple Distribution** certificate and a Mac App Store
      provisioning profile (the current Release configuration uses Developer ID
      for the `dev` channel; an App Store upload needs its own archive).
- [ ] Upload a build whose `CURRENT_PROJECT_VERSION` is higher than every
      previous upload for the version. The repository keeps build 1; bump it
      per submission.
- [ ] Provide the 6.9" / 6.5" Mac screenshots (the two in `docs/` are the
      source material), description, keywords, support URL, and privacy policy
      URL.
- [ ] Answer the export-compliance and content-rights questions; the app
      declares no non-exempt encryption.
- [ ] Confirm the age rating and the "made for macOS" availability.
- [ ] Complete the App Privacy questionnaire as “Data Not Collected”, matching
      `PrivacyInfo.xcprivacy`.
- [ ] Review the local-network prompt copy: the first Bonjour search triggers
      it, and the app continues without discovery if the user declines.

## Reviewer notes worth including

The app is a viewer for a developer-run service (`adhd`) that listens on
loopback or the lab LAN. With no cluster running, the app shows its empty
state and stays fully navigable; the isotope chart, the boundary list and the
scenario catalog are static and need no service at all, so they can be
exercised on a clean Mac. The traffic-log reader is optional; the app opens an
`NSOpenPanel` and persists a security-scoped bookmark for the file the reviewer
chooses. No login, purchase, or account is required.

The build submitted here is the sandboxed configuration. The Scenarios panel in
that build copies the `lezz` command and the adhd pairing; it has no launch
controls. The Lab launcher is a separate, non-App-Store build that runs outside
the App Sandbox.
