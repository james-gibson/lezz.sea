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

- Copies the adhd `smoke_alarm` block that pairs adhd with that instance.
- Links each row to the YAML at the commit the catalog was transcribed from.
- In the **Lab build**, launches and stops the scenario (below).

It is static. It needs no cluster, no network, no smoke-alarm checkout, and no
file access, which is why it also renders in the empty state and inside the App
Sandbox without an extra entitlement.

## Pairing adhd

adhd watches a smoke-alarm through its `smoke_alarm` list
(`internal/config/config.go`):

```yaml
smoke_alarm:
  - name: "federation-mesh"
    endpoint: "http://127.0.0.1:18088"
    interval: 10s
```

The row copies this block with the sample's health port — or the running
instance's remapped port, when one is live. adhd appends `/status` to the
endpoint.

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
2. Derives a config:
   - `runtime.state_dir`, `lock_file` and `baseline_file` become absolute
     under `Application Support/LezzSea/Instances/<slug>-<offset>/`.
   - The health, auth, hosted and federation ports move by a per-instance
     offset, and self-references to those exact ports are rewritten.
3. Runs `lezz run ocd-smoke-alarm serve --config=<derived> --mode=headless`.
4. Polls `http://127.0.0.1:<health-port>/status` and shows running/unreachable.
5. Stops it with `lezz run ocd-smoke-alarm ops stop -pid-file <pid>`.

### Ports, not `127.0.0.N`

macOS only puts `127.0.0.1` on `lo0`. Binding `127.0.0.2` fails with
`EADDRNOTAVAIL` until someone adds an alias as root (`ifconfig lo0 alias …`).
The port offset gives the same isolation without touching the system network
configuration. It was verified with two scenarios running at once on
`127.0.0.1`.

### Caveats

- The offset is per live instance, in steps of 1000. A port held by something
  outside the app surfaces as an unreachable instance; stop it and relaunch to
  take the next slot.
- Multi-instance federation scenarios (mesh, chain, pool) still need peer
  addresses mapped across instances. The single-instance rewrite points them at
  the instance's own offset. That is the next launcher step.
- `npx`/`uvx` targets need a useful PATH; the launcher prepends
  `/opt/homebrew/bin` and `/usr/local/bin`.
- adhd pairing is copied, not written into a config or launched. The report
  row from `scanner.go` is not shown yet.

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
scenario also carries the health port used by the adhd block. When a sample
changes:

1. Update the entry's name, use case, note or health port.
2. Update `sourceCommit`/`sourceDate`.
3. Run the unit tests: they pin the count, unique files and names, the theme
   coverage, the shape of every command, URL and adhd block, the filter
   semantics, and the derived config's port/path rewrite.

The YAML remains the source of truth. If the catalog and a config disagree, the
config is right.
