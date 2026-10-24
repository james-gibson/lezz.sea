//
//  NuclideChart.swift
//  LezzSea
//
//  The isotope view of smoke-alarm's threat × mechanism matrix: each threat
//  class resolved into its isotopes, and the mechanisms that decay it drawn as
//  channels. See smoke-alarm/docs/adr/0012-the-isotope-view-is-the-chart-of-the-nuclides.md
//
//  Deliberately pure data plus arithmetic: no AppModel, no network, no file
//  access, no image assets. That is what lets the same view run inside a
//  WidgetKit extension, where none of those are available.
//
//  This is an exposure model, chosen for that reason, and the dosimetry
//  vocabulary is load-bearing rather than decorative: source term, pathway,
//  receptor, dose, and deterministic versus stochastic effect. The exposed
//  quantity is work and accumulated 42i distance, never radiation. There are
//  no radiological quantities here (no Bq, Gy, Sv) and none may be added.
//

import Foundation

enum NuclideChart {

    // MARK: - Status

    /// A channel's verdict, taken verbatim from the matrix in
    /// `docs/design-matrices.md` §2. `open` is not "unknown": it is a channel
    /// that was examined and does not close the threat.
    enum Status: String, CaseIterable, Identifiable, Sendable {
        case closed
        case partial
        case open

        var id: String { rawValue }

        /// The mark the SVG grid uses, so the two diagrams agree.
        var mark: String {
            switch self {
            case .closed: "●"
            case .partial: "◐"
            case .open: "○"
            }
        }

        var word: String {
            switch self {
            case .closed: "closed"
            case .partial: "partial"
            case .open: "open"
            }
        }

        /// Ordering for "best channel wins": a cell is as strong as its
        /// strongest channel, and no stronger.
        var rank: Int {
            switch self {
            case .closed: 2
            case .partial: 1
            case .open: 0
            }
        }
    }

    // MARK: - Mechanism

    /// The columns of §2, in the order the grid lays them out. `residence` is
    /// the mechanism's measured detection time from §5 where §5 measures one,
    /// and is a property of the mechanism, not of any single cell.
    enum Mechanism: String, CaseIterable, Identifiable, Sendable {
        case tiers
        case golden
        case tick
        case hydration
        case churn
        case isotropy
        case convene
        case helix
        case side

        var id: String { rawValue }

        var name: String {
            switch self {
            case .tiers: "membership tiers + pricing"
            case .golden: "golden derived reference"
            case .tick: "lagged tick window"
            case .hydration: "predictive hydration"
            case .churn: "churn yield at 50%"
            case .isotropy: "isotropic name space"
            case .convene: "convenience rule"
            case .helix: "helix in the lift"
            case .side: "side channel, 3 filters"
            }
        }

        /// The grid's column header, from the SVG.
        var code: String {
            switch self {
            case .tiers: "tiers"
            case .golden: "golden"
            case .tick: "tick"
            case .hydration: "hydration"
            case .churn: "churn"
            case .isotropy: "isotropy"
            case .convene: "conv"
            case .helix: "helix"
            case .side: "side"
            }
        }

        /// What the threat becomes once this channel acts. Every mechanism
        /// lowers the threat's energy and leaves it present and measurable;
        /// none annihilates it, which is why no cell in the matrix is immunity.
        var daughter: String {
            switch self {
            case .tiers: "priced"
            case .golden: "re-derived"
            case .tick: "windowed"
            case .hydration: "pre-warmed"
            case .churn: "over-provisioned"
            case .isotropy: "symmetrised"
            case .convene: "opaque"
            case .helix: "attributed"
            case .side: "localised"
            }
        }

        /// From §5 "Detection latency vs load", where a figure exists.
        var residence: String {
            switch self {
            case .tiers: "immediate"
            case .golden: "870 ms"
            case .tick: "10 s"
            case .hydration: "550 ms"
            case .churn: "1 epoch"
            case .isotropy: "469 ms at 40/s"
            case .convene: "immediate"
            case .helix: "50 s"
            case .side: "4.7 s at 40/s"
            }
        }
    }

    // MARK: - Channel and isotope

    /// One non-empty cell of §2, read as a decay channel.
    struct Channel: Identifiable, Hashable, Sendable {
        let mechanism: Mechanism
        let status: Status
        /// The cell's short token, e.g. "plateau" or "870 ms".
        let label: String

        var id: String { mechanism.rawValue }
    }

    /// A threat variant: the same class as its siblings, delivered differently.
    struct Isotope: Identifiable, Hashable, Sendable {
        let symbol: String
        /// Row index in §2, so the compact table keeps the document's order.
        let matrixIndex: Int
        let mass: Int
        /// The full threat name from §2.
        let name: String
        /// What fits inside a cell.
        let short: String
        let exposure: Exposure
        let channels: [Channel]

        var id: String { code }
        var code: String { "\(symbol)-\(mass)" }

        /// A cell is as strong as its strongest channel.
        var status: Status {
            channels.map(\.status).max { $0.rank < $1.rank } ?? .open
        }

        var hasOpenChannel: Bool { channels.contains { $0.status == .open } }
        var isIsomeric: Bool { channels.count > 1 }
    }

    /// What is exposed, to what, and by how much.
    ///
    /// This is the half of the model the nuclide chart cannot carry on its own:
    /// the chart is a source-term inventory, and an exposure needs a pathway
    /// and a receptor as well. The quantities are work and distance, not
    /// activity, and the split between a threshold effect and a probabilistic
    /// one is the reason a verdict is never a probability.
    struct Exposure: Hashable, Sendable {
        /// Deterministic effects have a threshold: past it, the outcome is
        /// certain. Stochastic effects are a probability that rises with dose.
        /// The distinction is what the matrix's `●` flattens away.
        enum Effect: String, Sendable {
            case deterministic
            case stochastic

            var word: String {
                switch self {
                case .deterministic: "deterministic"
                case .stochastic: "stochastic"
                }
            }
        }

        /// Source term: who emits the work.
        let source: String
        /// The surface the work crosses to reach the receptor.
        let pathway: String
        /// What accumulates in the receptor.
        let dose: String
        let effect: Effect
        /// The measured threshold or the measured probability.
        let effectNote: String
    }

    /// A threat class: one element, several isotopes.
    struct Element: Identifiable, Hashable, Sendable {
        let z: Int
        let symbol: String
        let name: String
        let isotopes: [Isotope]

        var id: Int { z }

        func isotope(mass: Int) -> Isotope? {
            isotopes.first { $0.mass == mass }
        }
    }

    // MARK: - Data

    /// Five classes, eleven isotopes, taken cell by cell from
    /// `smoke-alarm/docs/design-matrices.md` §2. Cells marked `·` are absent
    /// here rather than zeroed: a mechanism with no channel at that mass is
    /// not a mechanism scoring nothing, it is one that was never tuned to it.
    ///
    /// The exposure fields name the source term, the pathway and the dose, so
    /// the chart answers "exposed to what" and not only "how fast does it
    /// decay". Every figure is from §2, §5 or the ledger in §7.
    static let elements: [Element] = [
        Element(z: 1, symbol: "Fl", name: "flood", isotopes: [
            isotope("Fl", 1, matrix: 0, mass: 1,
                    name: "stale flood (10^6 alarms)", short: "stale",
                    source: "one actor, 10^6 alarms",
                    pathway: "alarm ingress",
                    dose: "filter occupancy",
                    effect: .deterministic,
                    note: "plateau: the filter stops moving, not a probability",
                    channels: [(.tiers, .closed, "plateau")]),
            isotope("Fl", 1, matrix: 1, mass: 2,
                    name: "pipelined flood", short: "pipelined",
                    source: "one actor, chained submissions",
                    pathway: "tick boundary",
                    dose: "chain skew",
                    effect: .deterministic,
                    note: "the whole chain ages out together",
                    channels: [(.tiers, .closed, "stale by shape"),
                               (.tick, .closed, "chain skew")]),
        ]),
        Element(z: 2, symbol: "Pr", name: "pressure", isotopes: [
            isotope("Pr", 2, matrix: 2, mass: 1,
                    name: "filter saturation (4x)", short: "saturation",
                    source: "4x design occupancy",
                    pathway: "route filter",
                    dose: "occupancy x 4",
                    effect: .stochastic,
                    note: "FP 0.82% at design, 54% at 4x",
                    channels: [(.tiers, .partial, "per-group"),
                               (.golden, .closed, "870 ms"),
                               (.helix, .partial, "period"),
                               (.side, .closed, "canary 16x")]),
            isotope("Pr", 2, matrix: 3, mass: 2,
                    name: "cohort eviction (30 rot)", short: "eviction",
                    source: "30 rotations of alarms",
                    pathway: "admission",
                    dose: "identity price, 7 vs 24",
                    effect: .deterministic,
                    note: "evicted at 30 rotations",
                    channels: [(.tiers, .partial, "priced"),
                               (.golden, .closed, "hydrate"),
                               (.hydration, .closed, "550 ms"),
                               (.side, .open, "not closed")]),
            isotope("Pr", 2, matrix: 8, mass: 3,
                    name: "load surge (work > 50%)", short: "surge",
                    source: "honest work above 50%",
                    pathway: "durable path",
                    dose: "seconds per tick",
                    effect: .deterministic,
                    note: "11.3 s pipeline in a 5 s tick",
                    channels: [(.tick, .partial, "10 s"),
                               (.hydration, .closed, "1:6 min"),
                               (.churn, .closed, "add capacity")]),
        ]),
        Element(z: 3, symbol: "Fg", name: "forgery", isotopes: [
            isotope("Fg", 3, matrix: 4, mass: 1,
                    name: "stamp forgery (guess)", short: "stamp",
                    source: "a guessing actor",
                    pathway: "stamp check",
                    dose: "distance 7",
                    effect: .deterministic,
                    note: "7 distance to the honeypot",
                    channels: [(.tiers, .closed, "7 tries"),
                               (.isotropy, .closed, "2^32"),
                               (.convene, .closed, "no format"),
                               (.helix, .closed, "commit")]),
            isotope("Fg", 3, matrix: 5, mass: 2,
                    name: "replay across ticks", short: "replay",
                    source: "a replayed packet",
                    pathway: "tick window",
                    dose: "1 epoch",
                    effect: .deterministic,
                    note: "issuance holds for one epoch",
                    channels: [(.tiers, .closed, "issuance"),
                               (.golden, .closed, "1 epoch"),
                               (.helix, .closed, "no period"),
                               (.side, .partial, "flag only")]),
        ]),
        Element(z: 4, symbol: "Dv", name: "derivation", isotopes: [
            isotope("Dv", 4, matrix: 6, mass: 1,
                    name: "competent derivation", short: "deriver",
                    source: "a peer deriving one step ahead",
                    pathway: "derivation rate",
                    dose: "work share",
                    effect: .deterministic,
                    note: "capped at 2x work",
                    channels: [(.tiers, .partial, "rate cap"),
                               (.tick, .closed, "10 s win"),
                               (.hydration, .closed, "550 ms"),
                               (.churn, .closed, "2x cap"),
                               (.isotropy, .closed, "parity"),
                               (.convene, .closed, "no claim"),
                               (.helix, .closed, "attribution"),
                               (.side, .closed, "99% local")]),
            isotope("Dv", 4, matrix: 7, mass: 2,
                    name: "common-mode drift", short: "drift",
                    source: "a shared clock or layout",
                    pathway: "residue lift",
                    dose: "difference 2d",
                    effect: .deterministic,
                    note: "2d shows up as a difference",
                    channels: [(.helix, .closed, "difference 2d")]),
        ]),
        Element(z: 5, symbol: "Pb", name: "probe", isotopes: [
            isotope("Pb", 5, matrix: 9, mass: 1,
                    name: "wall-following probe", short: "wall-follow",
                    source: "a biased prober",
                    pathway: "probe answer",
                    dose: "19 probes",
                    effect: .stochastic,
                    note: "99.9% in 10 turns, 18.8 s at 1/s",
                    channels: [(.isotropy, .closed, "469 ms"),
                               (.convene, .closed, "5.2x"),
                               (.helix, .closed, "isotropic")]),
            isotope("Pb", 5, matrix: 10, mass: 2,
                    name: "gate enumeration", short: "enumeration",
                    source: "the refusal oracle",
                    pathway: "gate order",
                    dose: "5 reasons = 2.32 bits",
                    effect: .stochastic,
                    note: "51x at 5 gates, 2048x at 8",
                    channels: [(.convene, .closed, "51x")]),
        ]),
    ]

    /// Widest element, so the chart reserves the same number of columns.
    static let maxMass = elements.map { $0.isotopes.map(\.mass).max() ?? 0 }.max() ?? 0

    /// Every isotope in §2's row order, for the compact table.
    static var allIsotopes: [Isotope] {
        elements.flatMap(\.isotopes).sorted { $0.matrixIndex < $1.matrixIndex }
    }

    /// The matrix cell for one isotope and one mechanism, or nil when §2 has a `·`.
    static func channel(_ isotope: Isotope, _ mechanism: Mechanism) -> Channel? {
        isotope.channels.first { $0.mechanism == mechanism }
    }

    /// Totals for the header, counted rather than typed.
    static var counts: (isotopes: Int, closed: Int, open: Int) {
        let isotopes = allIsotopes
        return (
            isotopes.count,
            isotopes.filter { $0.status == .closed }.count,
            isotopes.filter { $0.hasOpenChannel }.count
        )
    }

    /// Threshold effects and probabilistic ones, counted.
    static var effectCounts: (deterministic: Int, stochastic: Int) {
        let isotopes = allIsotopes
        return (
            isotopes.filter { $0.exposure.effect == .deterministic }.count,
            isotopes.filter { $0.exposure.effect == .stochastic }.count
        )
    }

    // MARK: - Construction

    private static func isotope(
        _ symbol: String,
        _ z: Int,
        matrix: Int,
        mass: Int,
        name: String,
        short: String,
        source: String,
        pathway: String,
        dose: String,
        effect: Exposure.Effect,
        note: String,
        channels: [(Mechanism, Status, String)]
    ) -> Isotope {
        Isotope(
            symbol: symbol,
            matrixIndex: matrix,
            mass: mass,
            name: name,
            short: short,
            exposure: Exposure(
                source: source,
                pathway: pathway,
                dose: dose,
                effect: effect,
                effectNote: note
            ),
            channels: channels.map { Channel(mechanism: $0.0, status: $0.1, label: $0.2) }
        )
    }
}
