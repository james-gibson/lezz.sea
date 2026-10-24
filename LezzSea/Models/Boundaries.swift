//
//  Boundaries.swift
//  LezzSea
//
//  The invariants the rest of the app depends on, and the evidence that holds
//  each one. Static by design: the app cannot run the tests, so it names them
//  and never claims they pass.
//
//  See smoke-alarm/docs/adr/0020-the-boundary-is-the-interface.md
//

import Foundation

enum Boundaries {

    /// What holds a rule. A test is evidence; a conformance gap is honest debt
    /// and is rendered as a gap, never as a pass.
    enum Evidence: Hashable {
        case test(String)
        case conformanceGap
    }

    struct Boundary: Identifiable, Hashable {
        let id: String
        /// The rule, stated as an invariant.
        let invariant: String
        /// The mechanism that keeps it true.
        let holdsBecause: String
        /// The failure it prevents.
        let brokenMeans: String
        let evidence: Evidence
    }

    static let all: [Boundary] = [
        Boundary(
            id: "residence",
            invariant: "Data residence is one tick",
            holdsBecause: "the side channel overwrites; it never accumulates",
            brokenMeans: "a correlation channel across turns",
            evidence: .test("TestDataResidenceIsOneTick")
        ),
        Boundary(
            id: "placement",
            invariant: "Placement is a pure function",
            holdsBecause: "rendezvous computes the owner; there is no directory",
            brokenMeans: "a directory, and an enumeration surface",
            evidence: .test("TestPlacementIsByFunctionNotDirectory")
        ),
        Boundary(
            id: "no-per-route",
            invariant: "Production has no per-route delivery",
            holdsBecause: "the observer verb is absent, not disabled",
            brokenMeans: "a correlator in every deployment",
            evidence: .conformanceGap
        ),
        Boundary(
            id: "helix",
            invariant: "The helix advances one per tick",
            holdsBecause: "the tick is the clock; the stride is not a knob",
            brokenMeans: "period 30 becomes 15, 10 or 6",
            evidence: .test("TestCoprimeHelicesReconstructTheIndex")
        ),
        Boundary(
            id: "priors",
            invariant: "Lab results import as priors",
            holdsBecause: "bounded below one tick of evidence, overridden locally",
            brokenMeans: "authority laundering through a coefficient",
            evidence: .conformanceGap
        ),
        Boundary(
            id: "redundancy",
            invariant: "Redundancy is three budgets",
            holdsBecause: "replicas, placement and parity are counted separately",
            brokenMeans: "availability with lost data",
            evidence: .test("TestRouteRedundancyIsNotBlockDurability")
        ),
    ]

    static var gaps: [Boundary] {
        all.filter { $0.evidence == .conformanceGap }
    }
}
