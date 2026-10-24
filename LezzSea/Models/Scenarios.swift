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
//  Launching a lab cluster from one of these is the next step, not this one.
//  ADR 0017 makes identity, key and port the launcher's responsibility, and
//  none of that belongs in a viewer until it can be done honestly.
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
        let theme: Theme
        /// A caveat worth knowing before running it, when the sample carries one.
        var note: String? = nil

        var id: String { file }

        /// The command smoke-alarm documents for a sample, from a checkout.
        var command: String {
            "go run ./cmd/ocd-smoke-alarm serve --config=configs/samples/\(file) --mode=foreground"
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
                theme: .transport
            ),
            Scenario(
                file: "npm-mcp-targets.yaml",
                name: "npx MCP target matrix",
                useCase: "Three npx packages — filesystem, memory, github — as stdio targets.",
                theme: .transport
            ),
            Scenario(
                file: "npm-sse.yaml",
                name: "npx SSE with token auth",
                useCase: "npx packages including GitHub and Brave Search, authenticated from the environment.",
                theme: .transport
            ),
            Scenario(
                file: "uvx-sse.yaml",
                name: "uvx MCP target matrix",
                useCase: "uvx packages for fetch, git, sqlite and time.",
                theme: .transport
            ),
            Scenario(
                file: "sse-remote-mixed.yaml",
                name: "Mixed remote SSE",
                useCase: "Remote SSE and strict HTTPS MCP/ACP targets.",
                theme: .transport,
                note: "The remote targets are disabled by default; enable them in the YAML to probe."
            ),
            Scenario(
                file: "hosted-mcp-acp.yaml",
                name: "Embedded hosted MCP/ACP",
                useCase: "A hosted MCP/ACP HTTP+SSE server that monitors itself.",
                theme: .transport
            )
        ]),

        Group(theme: .federation, scenarios: [
            Scenario(
                file: "federation-mesh.yaml",
                name: "Federation mesh",
                useCase: "A three-instance mesh that self-elects an introducer; no external targets.",
                theme: .federation,
                note: "Run three processes against the same config; each claims a slot on ports 5100–5102."
            ),
            Scenario(
                file: "federation-chain.yaml",
                name: "Federation chain",
                useCase: "A linear frontend → router → backend → persistence chain.",
                theme: .federation
            ),
            Scenario(
                file: "federation-star-hub.yaml",
                name: "Federation star hub",
                useCase: "A hub coordinator fanning out to specialist spokes.",
                theme: .federation
            ),
            Scenario(
                file: "federation-dependency.yaml",
                name: "Federation dependency graph",
                useCase: "A non-linear microservice dependency graph.",
                theme: .federation
            ),
            Scenario(
                file: "federation-pool.yaml",
                name: "Federation worker pool",
                useCase: "Identical worker pools with quorum semantics.",
                theme: .federation
            )
        ]),

        Group(theme: .warroom, scenarios: [
            Scenario(
                file: "a2a-handoff.yaml",
                name: "A2A handoff",
                useCase: "Agent-to-agent async handoff across planner, executor, reporter and monitor.",
                theme: .warroom
            ),
            Scenario(
                file: "secure-context-handoff.yaml",
                name: "Secure context handoff",
                useCase: "Scoped, encrypted context injection with a TTL.",
                theme: .warroom
            ),
            Scenario(
                file: "incident-session-ephemeral.yaml",
                name: "Ephemeral incident session",
                useCase: "A temporary incident bridge with per-participant scopes.",
                theme: .warroom
            ),
            Scenario(
                file: "escalation-chain.yaml",
                name: "Escalation chain",
                useCase: "An L1→L4 on-call escalation matrix plus pager.",
                theme: .warroom
            ),
            Scenario(
                file: "observer-mode.yaml",
                name: "Observer mode",
                useCase: "Read-only observers watching an incident.",
                theme: .warroom
            ),
            Scenario(
                file: "disaster-recovery-drill.yaml",
                name: "Disaster recovery drill",
                useCase: "A chaos/DR exercise with fast timeouts.",
                theme: .warroom
            )
        ]),

        Group(theme: .auth, scenarios: [
            Scenario(
                file: "oauth-mock-allow.yaml",
                name: "OAuth mock (allow)",
                useCase: "An OAuth mock redirect in allow mode.",
                theme: .auth
            ),
            Scenario(
                file: "oauth-mock-fail.yaml",
                name: "OAuth mock (fail)",
                useCase: "An OAuth mock redirect in fail mode.",
                theme: .auth
            ),
            Scenario(
                file: "compliance-audit.yaml",
                name: "Compliance audit",
                useCase: "Audit logging, redaction and capability enforcement.",
                theme: .auth
            ),
            Scenario(
                file: "multitenancy-isolation.yaml",
                name: "Multitenancy isolation",
                useCase: "Tenant A/B/C isolation with distinct scopes.",
                theme: .auth
            ),
            Scenario(
                file: "secrets-rotation.yaml",
                name: "Secrets rotation",
                useCase: "Short-lived OAuth tokens and rotating API keys.",
                theme: .auth
            )
        ]),

        Group(theme: .deployment, scenarios: [
            Scenario(
                file: "deployment-canary.yaml",
                name: "Deployment canary",
                useCase: "A blue/green canary rollout with version gates.",
                theme: .deployment
            ),
            Scenario(
                file: "deployment-ha.yaml",
                name: "Deployment HA",
                useCase: "Two primaries plus a shared store and load balancer.",
                theme: .deployment
            ),
            Scenario(
                file: "cost-control.yaml",
                name: "Cost control",
                useCase: "Per-request cost awareness and rate-limit handling.",
                theme: .deployment
            ),
            Scenario(
                file: "tuner-integration.yaml",
                name: "Tuner integration",
                useCase: "mDNS advertisement, audience metrics and a caller hook for Tuner.",
                theme: .deployment
            )
        ]),

        Group(theme: .discovery, scenarios: [
            Scenario(
                file: "llmstxt-auto-discovery.yaml",
                name: "llms.txt auto-discovery",
                useCase: "Authoritative llms.txt discovery with auto-registration.",
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
