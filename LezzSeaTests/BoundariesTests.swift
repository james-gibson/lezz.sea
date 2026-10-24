//
//  BoundariesTests.swift
//  LezzSeaTests
//
//  The panel is an index of the rules, not a verifier. These tests pin the
//  index: every row says what it prevents, every test row names a test, and
//  the gaps stay gaps rather than quietly becoming passes.
//

import Testing
@testable import LezzSea

struct BoundariesTests {

    @Test func everyBoundaryIsFullyStated() {
        for boundary in Boundaries.all {
            #expect(!boundary.invariant.isEmpty)
            #expect(!boundary.holdsBecause.isEmpty)
            #expect(!boundary.brokenMeans.isEmpty)
        }
    }

    @Test func everyTestRowNamesATest() {
        for boundary in Boundaries.all {
            if case .test(let name) = boundary.evidence {
                #expect(!name.isEmpty)
                #expect(name.hasPrefix("Test"))
            }
        }
    }

    @Test func gapsAreCountedAsGaps() {
        // Two conformance gaps today: no per-route delivery, and the prior
        // import path. If this changes, the counter in the footer must change
        // with it.
        #expect(Boundaries.gaps.count == 2)
        #expect(Boundaries.gaps.allSatisfy { $0.evidence == .conformanceGap })
    }

    @Test func invariantsAreUnique() {
        let ids = Boundaries.all.map(\.id)
        #expect(Set(ids).count == ids.count)
    }
}
