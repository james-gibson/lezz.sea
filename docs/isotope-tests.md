# Isotope tests

LezzSea is the **observation layer**. The KB cluster and its scopes are the
**subject**. The isotope tests are the live scans that ask whether the observed
fleet is in the posture LezzSea is meant to show:

| scan | question |
|---|---|
| `verify-empty` (gate) | does an un-handshaken caller see an empty cluster? |
| `verify-empty --proxy` | is the dedicated KB proxy empty? |
| `verify-security` | empty façade, read/write/exec keys, negotiation, inverse rotation, honeypot, event |
| `verify-rotations` | is each proxy counter-rotating on the shared period? |
| `negotiate <scope>` | does the KB get a verified isotope receipt from the proxy? |

The `.feature` files in the KB checkout are the **identities** of these tests.
The KB suite validates each file against the isotope canon, then runs the scans.
The manifest is stable for LezzSea:

```json
{
  "schema": "lezzsea.isotope-tests/v1",
  "suite": "lezzsea.isotope-tests",
  "subject": "kb-cluster",
  "generated_at": "...",
  "tests": [
    {"name": "handshake-tumble", "file": "features/handshake-tumble.feature",
     "isotope": "5nhj...", "clean": true, "exit": 0}
  ],
  "behavior": {
    "verify_empty_gate": {"ok": true, "exit": 0},
    "verify_empty_proxy": {"ok": true, "exit": 0},
    "verify_security": {"ok": true, "exit": 0},
    "verify_rotations": {"ok": true, "exit": 0},
    "negotiate": {"openttd": {"ok": true, "exit": 0}}
  },
  "ok": true
}
```

## Run

```sh
scripts/isotope-tests.sh
```

That runs the KB launcher, writes `build/isotope-tests.json`, and prints a
summary. The launcher defaults to `~/projects/kb/scripts/cluster/kb-cluster.sh`;
override with `--kb-cluster` or `KB_CLUSTER`.

```sh
scripts/isotope-tests.sh --kb-cluster ~/projects/kb/scripts/cluster/kb-cluster.sh
scripts/isotope-tests.sh --output build/evidence/isotope-tests.json
scripts/isotope-tests.sh --manifest build/isotope-tests.json   # validate only
```

Exit `0` means every canon test is clean and every scan passed; `2` means a
failure or a non-`ok` manifest. The JSON is written even when the launcher exits
non-zero, so a failing run still leaves evidence.

## Decoder

`LezzSea/Models/IsotopeTestsManifest.swift` decodes the manifest and keeps the
failures addressable:

```swift
let manifest = try IsotopeTestsManifestLoader.load(from: url)
manifest.isSupported          // schema == lezzsea.isotope-tests/v1
manifest.isPassing            // ok + every test/scan/negotiation agrees
manifest.cleanCount
manifest.failedTests          // [CanonTest]
manifest.failedBehavior       // ["verify_security", ...]
manifest.failedNegotiations   // ["openttd", ...]
manifest.summary              // "8/8 clean · 11/11 negotiate · ok"
```

`ok: false` is **not** a decoding error: the app needs to display the exact
failure. Only malformed JSON or an unknown schema throws
(`IsotopeTestsManifestError.unsupportedSchema`). A missing `negotiate` map
decodes as empty, so an older manifest remains readable.

The sandboxed build cannot open an arbitrary path; pass a security-scoped URL
the app already has access to, or load the manifest from a Lab build/CLI. The
model and decoder themselves are pure Foundation, so they are safe to reuse in a
view or a widget.

Tests: `LezzSeaTests/IsotopeTestsManifestTests.swift` (7 cases: current shape,
schema rejection, failing suite, missing negotiate, optional/null fields,
unknown keys, disk load).

## What this is not

- It is not the **Isotopes** panel. That panel is smoke-alarm's static
  threat × mechanism chart and needs no cluster. These tests are the live
  security/observation scans of a running KB fleet.
- It is not `verify-exposure`. That is the red-team exposure _measurement_
  (`kb/scripts/lab/MCP-EXPOSURE-RISK.md`); it exits `2` while the KB raw adhd and
  registry are open, and is deliberately outside the pass/fail suite.
- It is not a sandboxed-app feature. The scans spawn local processes and read
  loopback endpoints; run them from the CLI or a Lab build, as the same user,
  with the KB fleet up.

## Why the identity matters

A scan that changes its Gherkin text is a different isotope test, even if the
name is the same. The manifest carries both the file and the derived isotope, so
a LezzSea run can say _which_ test it ran, not just that a scan passed. The
suite fails on a canon mismatch rather than silently accepting a relabelled
test.
