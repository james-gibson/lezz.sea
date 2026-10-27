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
- In the **Lab build**, or in any build started by `lezz sea run`, launches and
  stops a single-process scenario (below). The sandboxed build sends the
  request over a private channel; it never execs.
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

The launcher also pairs adhd by itself — directly in the Lab build, or through
lezz.go when it was started with `lezz sea run`: once every member answers, it
writes `<cluster>/adhd.yaml` (the same `smoke_alarm` entries, an
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

### The watcher report

`WatcherReport` (`LezzSea/Models/WatcherReport.swift`) ports the half of adhd's
`internal/report/scanner.go` that a paired instance can produce. The scanner
aggregates two kinds of evidence: MCP request/response lines, and the
`light-update` lines the smokelink watcher writes. A paired adhd writes only the
second kind, so the row scores `features/adhd/smoke-alarm-network.feature`'s
watcher scenarios: polling, light naming, status mapping, SSE, transitions,
multiple endpoints, graceful unavailability, proxy visibility and convergence.

The row reads `Gherkin report · 7 pass · 1 fail · 1 no coverage` and expands to
each scenario with its evidence (`1 poll events across 1 endpoint(s)`). A
scenario whose evidence has not happened yet is NO COVERAGE, not FAIL — the same
distinction `matcher.go` makes. **Copy Gherkin report** copies the rows as text.

Two limits are deliberate:

- It scores the Gherkin adhd ships for `smoke-alarm-network`, not the sample's
  own `.feature` file. `scanner.go` only defines specs for adhd's domains;
  pointed at smoke-alarm's features it returns NOT VERIFIABLE for every row.
- The MCP half needs adhd's own feature files and its own MCP traffic. A paired
  instance loads the checkout's features but serves no adhd MCP traffic of its
  own, so those rows would all be NOT VERIFIABLE too.

## Launching

macOS refuses to start an external process from the sandbox. An SMAppService
agent does not solve that: Apple requires a sandboxed app's agent to be
sandboxed too, and a sandboxed agent cannot exec `lezz` (registration returns
`Operation not permitted`). There are two supported launch paths:

- the **Lab build**, which has no App Sandbox and execs directly; or
- the sandboxed build started by **`lezz sea run`**, which asks lezz.go over a
  private stdin/stdout channel and lets lezz.go exec outside the sandbox.

A Finder launch of the sandboxed build has no channel, so its rows only copy.

The launcher:

1. Reads the selected sample.
2. Derives a config per member (see below).
3. Writes `cluster.json` before starting anything, so a failed launch is still
   stoppable.
4. Starts the members:
   - Lab build: `lezz run ocd-smoke-alarm serve --config=<derived>
     --mode=headless` once per member.
   - Channel: sends `{want:"start", cluster, members:[{name, config}]}`. The
     YAML travels as data; lezz.go writes it under
     `~/.lezz/sea/Clusters/<slug>/member-N/config.yaml`, creates the state
     directory, and runs the same `serve --mode=headless` argv there.
5. Asks the federation root `<base_port>/membership` whether the cluster is
   whole, and finds the health port each member bound by scanning loopback
   upward from the preferred port and accepting a port only when `/status`
   names that member's isotope. The mDNS advertisement is used when it answers;
   loopback does not depend on the local-network permission mDNS needs.
6. Pairs adhd (see above) once every member answers:
   - Lab build: writes and starts `<cluster>/adhd.yaml`.
   - Channel: sends `{want:"adhd", slug, healthPorts, gherkinDirectory}`;
     lezz.go picks the free port in 9190–9289, writes the config and starts
     adhd. The reply carries the endpoint and file paths recorded in
     `cluster.json`.
7. Stops adhd and then the alarms. The Lab build runs `lezz run
   ocd-smoke-alarm ops stop -pid-file <pid>`; the channel sends `{want:"stop",
   cluster}` and lezz.go stops the processes and removes their pid files.

### Why the channel carries the YAML

The app's own container is not its lab. TCC keeps other processes out of
`~/Library/Containers/co.jamesgibson.LezzSea`, so lezz.go cannot read a config the
app wrote there, and an alarm started by lezz.go could not write its state
there either. The request therefore carries the derived YAML itself; lezz.go
owns `~/.lezz/sea/Clusters`, writes the config and state under it, and the app
keeps only `cluster.json` in its container for display. The row's
`Reveal` action is a channel request because the paths are outside the app's
sandbox.

The channel is not a general remote control. The app sends a cluster slug and
derived YAML, never a binary or argv; the supervisor's verbs are `start`,
`stop`, `adhd` and `reveal`, and it rejects a config whose runtime paths are not
under its lab root. See lezz.go's `internal/sea` for the wire shape.

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
- adhd pairing is written and launched by the app in the Lab build, or by
  lezz.go in channel mode, and recorded in `cluster.json`;
  `scripts/lab-cluster.sh --pair-adhd` does the same from outside either. The row then scores the **watcher** half of `scanner.go`'s report
  from the paired adhd's log (below). The MCP-request half is not shown: it
  needs adhd's own `features/adhd/*.feature`, which a paired instance does not
  load, so it would report only NOT VERIFIABLE.

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
app, waits for the bound port, and stops it. Both skip in the sandboxed build
the UI tests launch: that build has no channel, so it cannot launch, and it does
not see the script's cluster. The sandboxed app started by `lezz sea run` does
launch (through the channel), but the UI tests do not start it that way.
