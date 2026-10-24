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
- Copies the command smoke-alarm documents for a sample:
  `go run ./cmd/ocd-smoke-alarm serve --config=configs/samples/<file>
  --mode=foreground`.
- Links each row to the YAML at the commit the catalog was transcribed from.

It is static. It needs no cluster, no network, no smoke-alarm checkout, and no
file access, which is why it also renders in the empty state and inside the App
Sandbox without an extra entitlement.

## What is deliberately not here

- **Launching.** Starting a lab cluster means minting an identity, provisioning
  a key and choosing a port. [ADR 0017](https://github.com/james-gibson/smoke-alarm/blob/main/docs/adr/0017-a-maladaptive-cluster-is-a-lab-strain.md)
  makes those the launcher's responsibility. A viewer that pretends to launch
  would either skip them or hide them; both are worse than copying a command.
- **Live reading of the checkout.** Parsing arbitrary YAML would add a parser
  and a folder grant for data that changes rarely. The catalog is transcribed
  and pinned to a commit instead.
- **Generated and harness configs.** `mcp-add-meta-*.yaml` is generated output,
  and `configs/samples/dev` + `qa` are the observer/QA harness. They are not
  scenarios an operator picks, so they are omitted.
- **Port-collision checks.** Several samples bind fixed health and hosted ports.
  Running two at once is a launcher concern, not a catalog concern.

## Keeping it honest

`ScenarioCatalog.sourceCommit` and `sourceDate` in
`LezzSea/Models/Scenarios.swift` record where the entries came from. When a
sample changes:

1. Update the entry's name, use case or note.
2. Update `sourceCommit`/`sourceDate`.
3. Run the unit tests: they pin the count, unique files and names, the theme
   coverage, the shape of every command and URL, and the filter semantics.

The YAML remains the source of truth. If the catalog and a config disagree, the
config is right.
