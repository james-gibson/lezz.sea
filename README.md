# lezz.sea

A small macOS app for watching an [adhd](https://github.com/james-gibson/adhd)
cluster: the lights it reports, and the MCP traffic it logs, live.

![Lights](docs/lights.png)

![Events](docs/events.png)

## What it does

- **Lights.** Reads `adhd.lights.list` and `adhd.status` from the selected
  cluster on a configurable interval. Green / red / yellow / dark, with the
  instance name and its 42i trust rung.
- **Events.** Follows adhd's JSONL MCP traffic log — one row per request,
  response, and light update, filterable and searchable, with the raw line on
  the context menu.
- **Discovery.** Checks the lezz cluster registry (`:19100/cluster`), probes the
  default adhd endpoint (`127.0.0.1:9090/mcp`), and watches Bonjour for
  `_adhd-isotope._tcp`.
- **Drop targets.** Drop a `.jsonl` log to stream it. Drop a `.yaml` / `.json`
  config (an `mcp_server.addr`, or any URL ending `/mcp`) to add its cluster.
- **Standard macOS chrome.** Menu commands, a Settings window, a search field,
  a status bar, and the usual keyboard shortcuts.

## Build

macOS 14.8 or later, Xcode 16.

```sh
open LezzSea.xcodeproj
```

or from the command line:

```sh
xcodebuild -project LezzSea.xcodeproj -scheme LezzSea \
  -configuration Debug -destination 'platform=macOS' build
```

Run the unit tests with:

```sh
xcodebuild -project LezzSea.xcodeproj -scheme LezzSea \
  -destination 'platform=macOS' test
```

## Using it

| Action | Shortcut |
| --- | --- |
| Add a cluster | ⌘N |
| Open an adhd log | ⌘O |
| Refresh lights | ⌘R |
| Discover clusters | ⇧⌘R |
| Lights tab | ⌘1 |
| Events tab | ⌘2 |
| Pause the event stream | ⇧⌘P |
| Clear events | ⌘K |
| Settings | ⌘, |

The event stream defaults to `~/Library/Logs/kb-adhd.jsonl`, the idle launchd
agent's log (`scripts/adhd` in the vault). Use **File ▸ Open adhd Log…** or the
Settings window to follow another instance's log — `spin.sh` instances write
`~/Library/Logs/kb-adhd-<name>.jsonl`.

## Notes on the design

- **Two MCP calls, no SDK.** adhd answers `adhd.status` and
  `adhd.lights.list` directly as JSON-RPC methods, so the client is a small
  `URLSession` wrapper instead of an MCP transport.
- **The log is the live channel.** adhd's `/mcp` SSE stream carries server
  frames only; the JSONL log is where every request and response actually
  appears. Watching it is the honest live view.
- **App Sandbox is off.** The app reads a log outside its container
  (`~/Library/Logs`) and only talks to loopback. If you want to ship it through
  the App Store, turn the sandbox on, add
  `com.apple.security.network.client`, and keep the security-scoped bookmark
  from the log picker.
- **No third-party dependencies.**

## Layout

```
LezzSea/
  LezzSeaApp.swift          App, Window, Settings scenes
  AppModel.swift            selection, polling, discovery, log tail
  Models/CoreModels.swift   lights, status, clusters, traffic events
  Services/                 JSON-RPC client, file tail, Bonjour, URL normalising
  Views/                    sidebar, dashboard, lights table, event stream, settings
```

The measure behind the rung and the light colours is described in the vault:
`scripts/lab/PLANE.md`, `scripts/lab/MATH.md`, and `scripts/lab/SPLASH.md`.
