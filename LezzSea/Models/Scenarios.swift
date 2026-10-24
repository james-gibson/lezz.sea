//
//  Scenarios.swift
//  LezzSea
//
//  smoke-alarm ships ready-to-run configs for the scenarios it knows how to
//  exercise. They are the lab's shapes: a federation mesh, an OAuth failure, a
//  canary rollout. This is that catalog, transcribed so the app can show what
//  the alarm can be asked to do without the user leaving the dashboard.
//
//  The YAML files are the source of truth. This list is derived; when a sample
//  changes, re-sync the entry and the `sourceCommit` below. Generated configs
//  and the dev/QA harness are deliberately left out: they are not scenarios an
//  operator picks.
//
//  Launching a single-process scenario is the Lab build's job; a multi-process
//  cluster is started by scripts/lab-cluster.sh until the launcher's discovery
//  has been verified against one. ADR 0017 makes identity, key and port the
//  launcher's responsibility, and none of that belongs in a viewer until it
//  can be done honestly.
//

import Foundation

enum ScenarioCatalog {

    // MARK: - Themes

    enum Theme: String, CaseIterable, Identifiable, Sendable {
        case transport
        case federation
        case warroom
        case auth
        case deployment
        case discovery

        var id: String { rawValue }

        var title: String {
            switch self {
            case .transport: "Transport & protocol"
            case .federation: "Federation & topology"
            case .warroom: "Warroom & incidents"
            case .auth: "Auth, secrets & compliance"
            case .deployment: "Deployment & operations"
            case .discovery: "Discovery & generated configs"
            }
        }

        var summary: String {
            switch self {
            case .transport: "stdio probes, SSE remotes, embedded hosting, npx/uvx packages"
            case .federation: "mesh, chain, star hub, dependency graph, worker pool"
            case .warroom: "A2A handoff, secure context, escalation, observers, DR drill"
            case .auth: "OAuth mock, tenant isolation, secret rotation, audit"
            case .deployment: "canary, HA failover, cost control, Tuner integration"
            case .discovery: "llms.txt auto-discovery"
            }
        }

        var symbol: String {
            switch self {
            case .transport: "arrow.left.arrow.right"
            case .federation: "circle.hexagongrid"
            case .warroom: "person.3"
            case .auth: "lock.shield"
            case .deployment: "shippingbox"
            case .discovery: "dot.radiowaves.left.and.right"
            }
        }
    }

    // MARK: - One scenario

    struct Scenario: Identifiable, Hashable, Sendable {
        /// The file name under `configs/samples/`, also the stable identity.
        let file: String
        let name: String
        let useCase: String
        /// The health server's port in the sample, used to pair adhd with it.
        let healthPort: Int
        let theme: Theme
        /// How many processes one lab cluster of this scenario runs. Only
        /// samples that document a run count set this above one; the rest are
        /// a single alarm whose topology lives in `targets`.
        var processes: Int = 1
        /// A caveat worth knowing before running it, when the sample carries one.
        var note: String? = nil

        var id: String { file }

        /// The file stem, used as the instance name in an adhd config.
        var slug: String {
            file.replacingOccurrences(of: ".yaml", with: "")
        }

        /// True when the app's launcher can start it. Multi-process clusters
        /// are launched with `scripts/lab-cluster.sh` until the launcher's
        /// discovery has been verified against them.
        var isLaunchable: Bool { processes == 1 }

        /// The command the lab uses to start a managed tool. `lezz` owns the
        /// binary, so the viewer points at the launcher rather than at a Go
        /// checkout.
        var command: String {
            "lezz run ocd-smoke-alarm serve --config=configs/samples/\(file) --mode=foreground"
        }

        /// The `smoke_alarm` block adhd needs to watch this instance. It is a
        /// fragment: paste it under the key in adhd's config. `features` and
        /// `gherkin_files` are a separate decision because they depend on
        /// where the smoke-alarm checkout lives.
        ///
        /// Pass the running instance's ports when they exist: the alarm
        /// self-negotiates its health port, so the sample's port is only the
        /// first member's preference. One entry per member keeps a federation
        /// cluster visible to adhd as more than its leader.
        func adhdSmokeAlarmBlock(healthPorts: [Int] = []) -> String {
            let ports = healthPorts.isEmpty ? [healthPort] : healthPorts
            let entries = ports.enumerated().map { offset, port in
                let name = ports.count == 1 ? slug : "\(slug)-\(offset + 1)"
                return """
                  - name: "\(name)"
                    endpoint: "http://127.0.0.1:\(port)"
                    interval: 10s
                """
            }
            return (["smoke_alarm:"] + entries).joined(separator: "\n")
        }

        /// A single-port block, for the common one-process case.
        func adhdSmokeAlarmBlock(healthPort: Int?) -> String {
            adhdSmokeAlarmBlock(healthPorts: [healthPort ?? self.healthPort])
        }


        /// The config at the commit this catalog was transcribed from.
        var url: URL {
            URL(
                string: "https://github.com/james-gibson/smoke-alarm/blob/"
                    + "\(ScenarioCatalog.sourceCommit)/configs/samples/\(file)"
            )!
        }
    }

    struct Group: Identifiable, Sendable {
        let theme: Theme
        let scenarios: [Scenario]

        var id: Theme { theme }
    }

    // MARK: - Provenance

    /// The smoke-alarm commit the entries were read from.
    static let sourceCommit = "a2866c3"
    static let sourceDate = "2026-10-20"

    // MARK: - Catalog

    static let groups: [Group] = [
        Group(theme: .transport, scenarios: [
            Scenario(
                file: "stdio-mcp-strict.yaml",
                name: "Strict stdio MCP",
                useCase: "An npx filesystem server behind a strict stdio MCP handshake.",
                healthPort: 18188,
                theme: .transport
            ),
            Scenario(
                file: "npm-mcp-targets.yaml",
                name: "npx MCP target matrix",
                useCase: "Three npx packages — filesystem, memory, github — as stdio targets.",
                healthPort: 18189,
                theme: .transport
            ),
            Scenario(
                file: "npm-sse.yaml",
                name: "npx SSE with token auth",
                useCase: "npx packages including GitHub and Brave Search, authenticated from the environment.",
                healthPort: 18189,
                theme: .transport
            ),
            Scenario(
                file: "uvx-sse.yaml",
                name: "uvx MCP target matrix",
                useCase: "uvx packages for fetch, git, sqlite and time.",
                healthPort: 18190,
                theme: .transport
            ),
            Scenario(
                file: "sse-remote-mixed.yaml",
                name: "Mixed remote SSE",
                useCase: "Remote SSE and strict HTTPS MCP/ACP targets.",
                healthPort: 18088,
                theme: .transport,
                note: "The remote targets are disabled by default; enable them in the YAML to probe."
            ),
            Scenario(
                file: "hosted-mcp-acp.yaml",
                name: "Embedded hosted MCP/ACP",
                useCase: "A hosted MCP/ACP HTTP+SSE server that monitors itself.",
                healthPort: 18088,
                theme: .transport
            )
        ]),

        Group(theme: .federation, scenarios: [
            Scenario(
                file: "federation-mesh.yaml",
                name: "Federation mesh",
                useCase: "A three-instance mesh that self-elects an introducer; no external targets.",
                healthPort: 18088,
                theme: .federation,
                processes: 3,
                note: "Three processes share ports 5100–5103 and 18088: the first claims the leader slot, the rest become followers that announce at the root."
            ),
            Scenario(
                file: "federation-chain.yaml",
                name: "Federation chain",
                useCase: "A linear frontend → router → backend → persistence chain.",
                healthPort: 18088,
                theme: .federation
            ),
            Scenario(
                file: "federation-star-hub.yaml",
                name: "Federation star hub",
                useCase: "A hub coordinator fanning out to specialist spokes.",
                healthPort: 18088,
                theme: .federation
            ),
            Scenario(
                file: "federation-dependency.yaml",
                name: "Federation dependency graph",
                useCase: "A non-linear microservice dependency graph.",
                healthPort: 18088,
                theme: .federation
            ),
            Scenario(
                file: "federation-pool.yaml",
                name: "Federation worker pool",
                useCase: "Identical worker pools with quorum semantics.",
                healthPort: 18088,
                theme: .federation
            )
        ]),

        Group(theme: .warroom, scenarios: [
            Scenario(
                file: "a2a-handoff.yaml",
                name: "A2A handoff",
                useCase: "Agent-to-agent async handoff across planner, executor, reporter and monitor.",
                healthPort: 18088,
                theme: .warroom
            ),
            Scenario(
                file: "secure-context-handoff.yaml",
                name: "Secure context handoff",
                useCase: "Scoped, encrypted context injection with a TTL.",
                healthPort: 18088,
                theme: .warroom
            ),
            Scenario(
                file: "incident-session-ephemeral.yaml",
                name: "Ephemeral incident session",
                useCase: "A temporary incident bridge with per-participant scopes.",
                healthPort: 18088,
                theme: .warroom
            ),
            Scenario(
                file: "escalation-chain.yaml",
                name: "Escalation chain",
                useCase: "An L1→L4 on-call escalation matrix plus pager.",
                healthPort: 18088,
                theme: .warroom
            ),
            Scenario(
                file: "observer-mode.yaml",
                name: "Observer mode",
                useCase: "Read-only observers watching an incident.",
                healthPort: 18088,
                theme: .warroom
            ),
            Scenario(
                file: "disaster-recovery-drill.yaml",
                name: "Disaster recovery drill",
                useCase: "A chaos/DR exercise with fast timeouts.",
                healthPort: 18088,
                theme: .warroom
            )
        ]),

        Group(theme: .auth, scenarios: [
            Scenario(
                file: "oauth-mock-allow.yaml",
                name: "OAuth mock (allow)",
                useCase: "An OAuth mock redirect in allow mode.",
                healthPort: 28088,
                theme: .auth
            ),
            Scenario(
                file: "oauth-mock-fail.yaml",
                name: "OAuth mock (fail)",
                useCase: "An OAuth mock redirect in fail mode.",
                healthPort: 29088,
                theme: .auth
            ),
            Scenario(
                file: "compliance-audit.yaml",
                name: "Compliance audit",
                useCase: "Audit logging, redaction and capability enforcement.",
                healthPort: 18088,
                theme: .auth
            ),
            Scenario(
                file: "multitenancy-isolation.yaml",
                name: "Multitenancy isolation",
                useCase: "Tenant A/B/C isolation with distinct scopes.",
                healthPort: 18088,
                theme: .auth
            ),
            Scenario(
                file: "secrets-rotation.yaml",
                name: "Secrets rotation",
                useCase: "Short-lived OAuth tokens and rotating API keys.",
                healthPort: 18088,
                theme: .auth
            )
        ]),

        Group(theme: .deployment, scenarios: [
            Scenario(
                file: "deployment-canary.yaml",
                name: "Deployment canary",
                useCase: "A blue/green canary rollout with version gates.",
                healthPort: 18088,
                theme: .deployment
            ),
            Scenario(
                file: "deployment-ha.yaml",
                name: "Deployment HA",
                useCase: "Two primaries plus a shared store and load balancer.",
                healthPort: 18088,
                theme: .deployment
            ),
            Scenario(
                file: "cost-control.yaml",
                name: "Cost control",
                useCase: "Per-request cost awareness and rate-limit handling.",
                healthPort: 18088,
                theme: .deployment
            ),
            Scenario(
                file: "tuner-integration.yaml",
                name: "Tuner integration",
                useCase: "mDNS advertisement, audience metrics and a caller hook for Tuner.",
                healthPort: 18088,
                theme: .deployment
            )
        ]),

        Group(theme: .discovery, scenarios: [
            Scenario(
                file: "llmstxt-auto-discovery.yaml",
                name: "llms.txt auto-discovery",
                useCase: "Authoritative llms.txt discovery with auto-registration.",
                healthPort: 18088,
                theme: .discovery
            )
        ])
    ]

    static let all: [Scenario] = groups.flatMap(\.scenarios)

    // MARK: - Filtering

    /// Groups filtered by a free-text query. Matches the name, file, use case
    /// and theme title so "oauth", "federation-mesh.yaml" and "warroom" all
    /// find their rows.
    static func filtered(_ query: String) -> [Group] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return groups }

        return groups.compactMap { group in
            let matches = group.scenarios.filter { scenario in
                scenario.name.lowercased().contains(needle)
                    || scenario.file.lowercased().contains(needle)
                    || scenario.useCase.lowercased().contains(needle)
                    || group.theme.title.lowercased().contains(needle)
            }
            return matches.isEmpty ? nil : Group(theme: group.theme, scenarios: matches)
        }
    }
}
