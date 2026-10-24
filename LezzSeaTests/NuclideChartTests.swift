//
//  NuclideChartTests.swift
//  LezzSeaTests
//
//  The chart is a transcription of smoke-alarm's design-matrices.md §2, so the
//  tests pin the transcription: every row present once, every channel a real
//  column, and the cells that are easy to round off left alone.
//

import Testing
@testable import LezzSea

struct NuclideChartTests {

    @Test func elevenRowsInDocumentOrder() {
        let isotopes = NuclideChart.allIsotopes
        #expect(isotopes.count == 11)
        #expect(isotopes.map(\.matrixIndex) == Array(0...10))
    }

    @Test func everyChannelIsAColumn() {
        let columns = Set(NuclideChart.Mechanism.allCases)
        for isotope in NuclideChart.allIsotopes {
            for channel in isotope.channels {
                #expect(columns.contains(channel.mechanism))
                #expect(!channel.label.isEmpty)
            }
        }
    }

    @Test func noThreatIsUnaddressed() {
        for isotope in NuclideChart.allIsotopes {
            #expect(!isotope.channels.isEmpty)
        }
    }

    @Test func cohortEvictionKeepsItsOpenChannel() {
        let isotope = NuclideChart.elements
            .flatMap(\.isotopes)
            .first { $0.name.hasPrefix("cohort eviction") }
        let side = isotope.flatMap { NuclideChart.channel($0, .side) }
        #expect(side?.status == .open)
        #expect(side?.label == "not closed")
        // The class still reports its best channel, and flags the open one.
        #expect(isotope?.status == .closed)
        #expect(isotope?.hasOpenChannel == true)
    }

    @Test func gateEnumerationHasOneChannel() {
        let isotope = NuclideChart.allIsotopes.first { $0.name.hasPrefix("gate enumeration") }
        #expect(isotope?.channels.count == 1)
        #expect(isotope?.channels.first?.mechanism == .convene)
        #expect(isotope?.channels.first?.label == "51x")
    }

    @Test func bestChannelWins() {
        let isotope = NuclideChart.allIsotopes.first { $0.name.hasPrefix("filter saturation") }
        // tiers is partial, golden is closed: the class reports closed.
        #expect(isotope?.status == .closed)
        #expect(isotope.flatMap { NuclideChart.channel($0, .tiers) }?.status == .partial)
    }

    @Test func widestElementSetsTheColumns() {
        #expect(NuclideChart.maxMass == 3)
        #expect(NuclideChart.elements.first { $0.symbol == "Pr" }?.isotopes.count == 3)
    }

    @Test func countsAreDerivedNotTyped() {
        let counts = NuclideChart.counts
        #expect(counts.isotopes == 11)
        #expect(counts.closed >= 0 && counts.closed <= counts.isotopes)
        #expect(counts.open >= 1)
    }

    @Test func everyIsotopeNamesItsExposure() {
        for isotope in NuclideChart.allIsotopes {
            #expect(!isotope.exposure.source.isEmpty)
            #expect(!isotope.exposure.pathway.isEmpty)
            #expect(!isotope.exposure.dose.isEmpty)
            #expect(!isotope.exposure.effectNote.isEmpty)
        }
    }

    @Test func bothEffectKindsArePresent() {
        let effects = NuclideChart.effectCounts
        // 8 threshold effects, 3 probabilistic ones — the split the ADR quotes.
        #expect(effects.deterministic == 8)
        #expect(effects.stochastic == 3)
        #expect(effects.deterministic + effects.stochastic == NuclideChart.allIsotopes.count)
    }
}
