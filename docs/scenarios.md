# Scenarios

The **Scenarios** panel is the app's copy of smoke-alarm's
[`configs/samples`](https://github.com/james-gibson/smoke-alarm/tree/main/configs/samples)
catalog: 27 ready-to-run configs, grouped by the theme each one exercises.

It exists because of the direction of adoption. lezz.sea watches an adhd
cluster; adhd watches smoke-alarm; smoke-alarm's samples are the shapes a lab
cluster can take. A launcher cannot offer a scenario it cannot name, so the
catalog comes first.

## What the panel does

- Lists every runnable sample by theme (transport, federation, warroom, auth,
  deployment, discovery).
- Filters by name, file, use case or theme.
- Copies the lab's launcher command:

  ```sh
  lezz run ocd-smoke-alarm serve --config=configs/samples/<file> --mode=foreground
  ```

- Copies the adhd `smoke_alarm` block that pairs adhd with that instance — one
  entry per member of the cluster when it is running.
- Links each row to the YAML at the commit the catalog was transcribed from.
- In the **Lab build**, launches and stops a single-process scenario (below).
- Shows any cluster described by `cluster.json`, including one a script
  started. That is deliberate: the UI is verified against a cluster it did not
  launch before it is trusted to launch multi-process clusters itself.

It is static. It needs no cluster, no network, no smoke-alarm checkout, and no
file access, which is why it also renders in the empty state and inside the App
Sandbox without an extra entitlement.

## Pairing adhd

adhd watches a smoke-alarm through its `smoke_alarm` list
(`internal/config/config.go`):

```yaml
smoke_alarm:
  - name: "federation-mesh-1"
    endpoint: "http://127.0.0.1:18088"
    interval: 10s
  - name: "federation-mesh-2"
    endpoint: "http://127.0.0.1:18089"
    interval: 10s
```

The row copies this block with the ports the members actually bound. adhd
appends `/status` to each endpoint, so a federation cluster stays visible to
adhd as more than its leader.

In the **Lab build** the launcher also pairs adhd by itself: once every member
answers, it writes `<cluster>/adhd.yaml` (the same `smoke_alarm` entries, an
`mcp_server.addr` on a free port in 9190–9289, and the checkout's
`features/*.feature` glob), starts `adhd --headless --config <cluster>/adhd.yaml`
with its output in `<cluster>/adhd.log`, and records the endpoint under the
`adhd` key in `cluster.json`. The row then reads `adhd: :9190 · N lights` and
offers **Reveal adhd log**; Stop stops adhd before the alarms. A machine without
adhd gets `adhd: not installed …` on the row — the alarm still runs.

For traceability, adhd's `features.binaries[].gherkin_files` points at the
smoke-alarm feature files. `internal/report/scanner.go` then cross-references
the JSONL traffic log against those Gherkin scenarios, so a scenario can be
scored rather than merely watched — the same log the app's Events panel reads.
Point the glob at the checkout:

```yaml
features:
  binaries:
    - name: ocd-smoke-alarm
      endpoint: "http://127.0.0.1:18088/status"
      gherkin_files:
        - "../smoke-alarm/features/*.feature"
```

## Launching (Lab build)

macOS refuses to start an external process from the sandbox. An SMAppService
agent does not solve that: Apple requires a sandboxed app's agent to be
sandboxed too, and a sandboxed agent cannot exec `lezz` (registration returns
`Operation not permitted`). Launching is therefore compiled into the **Lab**
build, which has no App Sandbox. The sandboxed build copies commands instead.

The Lab launcher:

1. Reads the selected sample.
2. Derives a config per member (see below).
3. Writes `cluster.json` before starting anything, so a failed launch is still
   stoppable.
4. Runs `lezz run ocd-smoke-alarm serve --config=<derived> --mode=headless`
   once per member.
5. Asks the federation root `<base_port>/membership` whether the cluster is
   whole, and finds the health port each member bound by scanning loopback
   upward from the preferred port and accepting a port only when `/status`
   names that member's isotope. The mDNS advertisement is used when it answers;
   loopback does not depend on the local-network permission mDNS needs.
6. Writes and starts a paired adhd (see above) once every member answers, and
   records its endpoint in `cluster.json`.
7. Stops adhd and then the alarms: `lezz run ocd-smoke-alarm ops stop -pid-file
   <pid>` per member.

### Ports are not moved; identity is rotated

A port is not how two instances are told apart. The alarm already negotiates:

- `health` binds its preferred port and scans upward on `EADDRINUSE`, then
  advertises the port it actually bound over mDNS;
- `federation` claims the first free slot in its range, so the first process
  becomes the introducer and the rest become followers that announce at the
  root (`http://localhost:<base_port>`).

The derived config therefore leaves every listener and slot port alone, and
changes four things instead:

| change | why |
| --- | --- |
| `service.name` becomes `<name>-<slug>-<n>` | it is the mDNS instance name, so three members need three names |
| `tuner.advertise: true` + `_smoke-alarm._tcp` | the advertisement carries the bound port for adhd, Tuner and any other consumer |
| `federation.cluster_id` kept only when the sample declares one | peers do not trust each other by default; a declared agreement is what mirrors members into each other's isotope lists at the peer-certified rung. The launcher never invents one and never fills an empty one, because pool, chain, star and dependency deliberately omit it |
| `runtime.*` paths become absolute and per-member | two members must not share a lock file or a baseline |

Nothing else is edited, and the sample is never modified: each launch writes
derived configs under
`Application Support/LezzSea/Clusters/<slug>/member-<n>/`.

### `cluster.json` is the contract

The launcher writes one file per scenario:

```json
{
  "scenarioID": "federation-mesh.yaml",
  "name": "Federation mesh",
  "slug": "federation-mesh",
  "clusterID": "federation-mesh-sample",
  "rootPort": 5100,
  "startedAt": "2026-10-24T05:27:46Z",
  "members": [
    {
      "index": 1,
      "isotope": "ocd-smoke-alarm-federation-mesh-1",
      "preferredHealthPort": 18088,
      "configPath": "/…/member-1/config.yaml",
      "pidPath": "/…/member-1/ocd-smoke-alarm.pid",
      "logPath": "/…/member-1/alarm.log",
      "stateDir": "/…/member-1/state"
    }
  ]
}
```

Anything that can write it can hand the UI a cluster, and the app treats that
cluster exactly like one it started. The verification script uses this: it
launches a cluster from outside the app, registers the same file, and the
Scenarios panel shows it.

The app shows a cluster as **running** only when the root names every member.
When the cluster carries a declared agreement, the members must also share it;
some members but not all is **partial**, and a root whose agreement differs is
**unreachable** — the port belongs to somebody else's stack.

That distinction is load-bearing. `cluster_id` is the sample's statement that
its members may trust each other *by construction*: mesh declares one, while
pool, chain, star and dependency do not. A sample that omits it still forms a
federation (the first process is the introducer, the rest follow) but nobody is
mirrored at the peer-certified rung, so a pool of identical workers does not
trust itself merely by sharing a pool. An empty value means the same thing
(`federation-mesh.yaml`: "Leave empty to disable self-trust").

### Multi-process clusters are launched by the script, for now

`federation-mesh.yaml` documents a three-process cluster. The app's row shows a
terminal button that copies the script command rather than a play button: the
launcher's discovery was verified against a script-launched cluster first, and
extending the launch button to N members is the next step.

```sh
scripts/lab-cluster.sh configs/samples/federation-mesh.yaml --pair-adhd
scripts/lab-cluster.sh --stop federation-mesh
```

The script:

- works in a `mktemp -d` directory under the per-user `$TMPDIR`, not `/tmp`, so
  a lab run is private and leaves no predictable path;
- derives the same configs the app does (same four changes);
- waits for self-negotiation, resolves each member's bound health port (mDNS
  first, then a name-checked loopback scan) and reports which channel answered,
  and verifies the root's membership plus every member's isotope list at rung 4;
- optionally writes an adhd config watching every member, starts it headless on
  a free port, and prints the endpoint to connect the UI to;
- registers `cluster.json` so the Scenarios panel shows the cluster.

### Caveats

- A port can still be lost to a process that is not an alarm: the health server
  scans upward, but `auth`, `hosted` and the OAuth mock redirect server do not.
  A sample that needs one of those shows up as an unreachable member, and its
  `member-<n>/alarm.log` says which port failed.
- `npx`/`uvx` targets need a useful PATH; the launcher prepends
  `/opt/homebrew/bin` and `/usr/local/bin`.
- adhd pairing is written and launched by the app in the Lab build, and recorded
  in `cluster.json`; `scripts/lab-cluster.sh --pair-adhd` does the same from
  outside it. The `scanner.go` report row is not shown yet: the report is not
  exposed over adhd's MCP surface, so there is nothing for the app to read.

## What is deliberately not here

- **Live reading of the checkout.** Parsing arbitrary YAML would add a parser
  and a folder grant for data that changes rarely. The catalog is transcribed
  and pinned to a commit instead; the Lab launcher reads only the sample the
  operator selected.
- **Generated and harness configs.** `mcp-add-meta-*.yaml` is generated output,
  and `configs/samples/dev` + `qa` are the observer/QA harness. They are not
  scenarios an operator picks, so they are omitted.

## Keeping it honest

`ScenarioCatalog.sourceCommit` and `sourceDate` in
`LezzSea/Models/Scenarios.swift` record where the entries came from. Each
scenario also carries the health port used by the adhd block and, when the
sample documents one, its process count. When a sample changes:

1. Update the entry's name, use case, note, health port or process count.
2. Update `sourceCommit`/`sourceDate`.
3. Run the unit tests: they pin the count, unique files and names, the theme
   coverage, the shape of every command, URL and adhd block, the filter
   semantics, and the derived config's isotope/state/agreement rewrite.

The YAML remains the source of truth. If the catalog and a config disagree, the
config is right.

## Verifying the UI against a cluster it did not launch

```sh
scripts/lab-cluster.sh configs/samples/federation-mesh.yaml --pair-adhd

xcodebuild -project LezzSea.xcodeproj -scheme LezzSea \
  -destination 'platform=macOS' \
  CODE_SIGN_ENTITLEMENTS=LezzSea/LezzSea-Lab.entitlements \
  SWIFT_ACTIVE_COMPILATION_CONDITIONS=LAB_LAUNCHER \
  ENABLE_APP_SANDBOX=NO ENABLE_USER_SELECTED_FILES= \
  test -only-testing:LezzSeaUITests/LabClusterUITests
```

The first test asserts that the Scenarios row reads `:5100 · 3/3` from the
script's cluster. The second launches a single-process scenario through the
app, waits for the bound port, and stops it. Both skip in the sandboxed build,
which cannot see launcher clusters.
