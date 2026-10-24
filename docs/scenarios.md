# Scenarios

The **Scenarios** panel is the app's copy of smoke-alarm's
[`configs/samples`](https://github.com/james-gibson/smoke-alarm/tree/main/configs/samples)
catalog: 27 ready-to-run configs, grouped by the theme each one exercises.

It exists because of the direction of adoption. lezz.sea watches an adhd
cluster; adhd watches smoke-alarm; smoke-alarm's samples are the shapes a lab
cluster can take. A launcher cannot offer a scenario it cannot name, so the
catalog comes first.

## What this build does

- Lists every runnable sample by theme (transport, federation, warroom, auth,
  deployment, discovery).
- Filters by name, file, use case or theme.
- Copies the lab's launcher command for a sample:

  ```sh
  lezz run ocd-smoke-alarm serve --config=configs/samples/<file> --mode=foreground
  ```

  `lezz` owns the managed binary, so this is the path the lab uses.
  `go run ./cmd/ocd-smoke-alarm …` remains the checkout-only fallback.
- Copies the adhd `smoke_alarm` block that pairs adhd with that instance.
- Links each row to the YAML at the commit the catalog was transcribed from.

It is static. It needs no cluster, no network, no smoke-alarm checkout, and no
file access, which is why it also renders in the empty state and inside the App
Sandbox without an extra entitlement.

## Pairing adhd

adhd watches a smoke-alarm through its `smoke_alarm` list
(`internal/config/config.go`):

```yaml
smoke_alarm:
  - name: "federation-mesh"
    endpoint: "http://localhost:18088"
    interval: 10s
```

The row copies this block with the sample's health port. adhd appends
`/status` to the endpoint.

For traceability, adhd's `features.binaries[].gherkin_files` points at the
smoke-alarm feature files. `internal/report/scanner.go` then cross-references
the JSONL traffic log against those Gherkin scenarios, so a scenario can be
scored rather than merely watched — the same log the app's Events panel reads.
Point the glob at the checkout:

```yaml
features:
  binaries:
    - name: ocd-smoke-alarm
      endpoint: "http://localhost:18088/status"
      gherkin_files:
        - "../smoke-alarm/features/*.feature"
```

## Launching

smoke-alarm is launchable from lezz.go (`lezz run`, or `lezz service install`
for a managed LaunchAgent). This build names that command but does not execute
it, for three reasons that belong to the launcher:

1. **The sandbox.** The app cannot spawn an external `lezz` or alarm binary.
   A launch has to go through LaunchServices to an installed Lezz.app, or
   through a helper bundle that the app ships and signs.
2. **Relative state.** The samples write `runtime.state_dir`,
   `lock_file` and `baseline_file` relative to the working directory, so a
   launch needs a derived config with absolute paths — or a controlled cwd.
3. **Fixed ports.** Many samples bind the same health or hosted port
   (`18088`, `18089`, `5100–5102`). Two scenarios cannot run side by side on
   one loopback address.

The planned isolation is a loopback address per instance: `127.0.0.N`. The
launcher derives a copy of the sample with its listeners and self-targets
rewritten to that address, keeps peer addresses pointing at their peers, writes
the copy under Application Support, and launches:

```sh
lezz run ocd-smoke-alarm serve --config=<derived-config>
```

The same `127.0.0.N` then goes into the adhd `smoke_alarm` block, so the lights
in the app belong to that instance and not to a neighbour. This is tracked in
[#6](https://github.com/james-gibson/lezz.sea/issues/6).

## What is deliberately not here

- **Live reading of the checkout.** Parsing arbitrary YAML would add a parser
  and a folder grant for data that changes rarely. The catalog is transcribed
  and pinned to a commit instead.
- **Generated and harness configs.** `mcp-add-meta-*.yaml` is generated output,
  and `configs/samples/dev` + `qa` are the observer/QA harness. They are not
  scenarios an operator picks, so they are omitted.
- **Port-collision checks.** The launcher owns those; see above.

## Keeping it honest

`ScenarioCatalog.sourceCommit` and `sourceDate` in
`LezzSea/Models/Scenarios.swift` record where the entries came from. Each
scenario also carries the health port used by the adhd block. When a sample
changes:

1. Update the entry's name, use case, note or health port.
2. Update `sourceCommit`/`sourceDate`.
3. Run the unit tests: they pin the count, unique files and names, the theme
   coverage, the shape of every command, URL and adhd block, and the filter
   semantics.

The YAML remains the source of truth. If the catalog and a config disagree, the
config is right.
