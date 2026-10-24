---
name: lab-cluster
description: Use when a smoke-alarm lab cluster has to exist for a UI check,
  a federation test, or an adhd pairing — starting one, verifying the
  self-negotiated ports and the isotope agreement, pairing adhd with it, and
  stopping it again. Trigger on: launch the test cluster, start the lab
  cluster, bring up federation-mesh, load a scenario cluster, verify the UI
  against a cluster, pair adhd with the alarm, stop the lab cluster, or when a
  UI test needs a cluster the app did not launch. Wraps
  scripts/lab-cluster.sh; do not hand-roll `lezz run` loops or inline sed
  rewrites of the samples.
---

# Lab cluster

`scripts/lab-cluster.sh` is the reference launcher for a smoke-alarm scenario.
It exists because the app's launcher has to be verified against a cluster it
did not start: the script starts the same shape from outside the app, writes the
same `cluster.json`, and checks the properties the UI depends on.

## When to use it

- A UI test or a manual UI check needs a running cluster
  (`LezzSeaUITests/LabClusterUITests.swift` skips without one).
- A federation change needs a real 3-member mesh: leader on the root port,
  followers announcing at the root, one agreement across all members.
- adhd has to be paired with every member of a cluster.
- Something is leaking ports or state and a clean, private run is needed.

Do not edit `configs/samples/*.yaml` to do any of this.

## Bring one up

From the lezz.sea checkout:

```sh
scripts/lab-cluster.sh federation-mesh.yaml --pair-adhd
```

The script resolves the sample from `$SMOKE_ALARM`, else
`~/projects/personal/smoke-alarm/configs/samples/`; pass `--checkout DIR` or an
absolute path when the checkout is elsewhere. It:

1. works in a fresh `mktemp -d` under the per-user `$TMPDIR` — never `/tmp`
   directly, so the run is private and leaves no predictable path;
2. derives one config per member: absolute `runtime.*` paths, `service.name`
   rotated to `<name>-<slug>-<n>`, `tuner.advertise` on with
   `_smoke-alarm._tcp`, and a shared `federation.cluster_id` when the sample
   does not declare one. **Ports are not remapped**;
3. starts the members and waits for self-negotiation. The first to bind
   `base_port` is the introducer; the rest become followers. Health ports scan
   upward from the sample's preferred port;
4. resolves each member's bound port over mDNS and verifies that the root's
   `/membership` names every member under one agreement, and that every member's
   `/isotope/list` mirrors the whole cluster at rung 4;
5. writes `cluster.json` into the work directory **and** into
   `~/Library/Application Support/LezzSea/Clusters/<slug>/cluster.json`, which
   is what the Lab build reads;
6. with `--pair-adhd`, writes an adhd config watching every member, starts adhd
   headless on a free port, and prints the endpoint.

Success looks like:

```
root :5100 introducer, 3/3 members, one agreement
agreement: federation-mesh-sample
isotopes: every member mirrors every other at rung 4
adhd: http://127.0.0.1:9190/mcp (N light(s))
```

A `FAIL` block names the exact property that did not hold (missing member, split
agreement, wrong rung). Read `member-<n>/alarm.log` in the printed work
directory before changing anything; the bound port and the elected role are
lines in it.

## Point the UI at it

The Lab build (not the sandboxed one) reads
`~/Library/Application Support/LezzSea/Clusters/`. The Scenarios row shows
`:5100 · 3/3` for a mesh, and the terminal button carries the script command
instead of a play button, because multi-process clusters are still launched by
this script.

Automated check:

```sh
xcodebuild -project LezzSea.xcodeproj -scheme LezzSea \
  -destination 'platform=macOS' \
  CODE_SIGN_ENTITLEMENTS=LezzSea/LezzSea-Lab.entitlements \
  SWIFT_ACTIVE_COMPILATION_CONDITIONS=LAB_LAUNCHER \
  ENABLE_APP_SANDBOX=NO ENABLE_USER_SELECTED_FILES= \
  test -only-testing:LezzSeaUITests/LabClusterUITests
```

The adhd endpoint printed by `--pair-adhd` is what you add to the dashboard (or
set as `defaultEndpoint` in the app's defaults) to see lights and events.

## Stop it

```sh
scripts/lab-cluster.sh --stop federation-mesh
```

That stops every member by its pid file, stops the paired adhd if the contract
records one, and removes the registered `cluster.json`. A `--no-register` run has
no registered copy, so `--stop` falls back to the newest work directory for that
slug. The work directory is kept for logs; remove it when the run is understood.

## Rules

- One launch per slug at a time: the registered `cluster.json` and the member
  directory are keyed by slug.
- Do not run two `lab-cluster.sh` invocations for the same sample in parallel;
  they share a slug and would fight over the contract file.
- If a run was interrupted before registration, `--stop <slug>` still finds the
  newest work directory's `cluster.json`; otherwise stop by the pid files in
  `member-<n>/`.
- `-72007`/`NoAuth` from `dns-sd` means the calling process lacks local network
  permission. The script falls back to a name-checked loopback scan; the app
  does the same, so a cluster is still usable, but the mDNS advertisement itself
  is then unverified — say so rather than claiming discovery works.
