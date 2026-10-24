//
//  ScenarioCatalogTests.swift
//  LezzSeaTests
//
//  The scenario catalog is a transcription of smoke-alarm's configs/samples.
//  The tests pin the parts that would drift silently: a missing sample, a
//  duplicate file, a command that no longer names its config, and a filter
//  that misses the field the user typed.
//

import Testing
@testable import LezzSea

struct ScenarioCatalogTests {

    @Test func catalogHasEveryRunnableSample() {
        #expect(ScenarioCatalog.all.count == 27)
        #expect(ScenarioCatalog.groups.count == 6)
    }

    @Test func everyThemeHasAtLeastOneScenario() {
        for theme in ScenarioCatalog.Theme.allCases {
            let group = ScenarioCatalog.groups.first { $0.theme == theme }
            #expect(group != nil, "theme \(theme.rawValue) has no group")
            #expect(!(group?.scenarios.isEmpty ?? true), "theme \(theme.rawValue) is empty")
        }
    }

    @Test func filesAndNamesAreUnique() {
        let files = ScenarioCatalog.all.map(\.file)
        let names = ScenarioCatalog.all.map(\.name)
        #expect(Set(files).count == files.count)
        #expect(Set(names).count == names.count)
    }

    @Test func everyScenarioIsRunnableAndLinksToItsConfig() {
        for scenario in ScenarioCatalog.all {
            #expect(scenario.command.hasPrefix("lezz run ocd-smoke-alarm serve"))
            #expect(scenario.command.contains("configs/samples/\(scenario.file)"))
            #expect(scenario.url.absoluteString.hasSuffix("/configs/samples/\(scenario.file)"))
            #expect(scenario.url.absoluteString.contains(ScenarioCatalog.sourceCommit))
            #expect(!scenario.useCase.isEmpty)
        }
    }

    @Test func everyScenarioHasAHealthPortAndAnAdhdBlock() {
        for scenario in ScenarioCatalog.all {
            #expect(scenario.healthPort > 0)
            #expect(scenario.adhdSmokeAlarmBlock.contains("endpoint: \"http://localhost:\(scenario.healthPort)\""))

            let lines = scenario.adhdSmokeAlarmBlock.split(separator: "\n")
            #expect(lines.first == "smoke_alarm:")
            #expect(lines.contains { $0.contains("name: \"\(scenario.slug)\"") })
            #expect(lines.contains { $0.contains("interval: 10s") })
        }
    }

    @Test func everyScenarioMatchesItsGroupTheme() {
        for group in ScenarioCatalog.groups {
            for scenario in group.scenarios {
                #expect(scenario.theme == group.theme)
            }
        }
    }

    @Test func emptyFilterReturnsTheWholeCatalog() {
        let groups = ScenarioCatalog.filtered("   ")
        #expect(groups.count == ScenarioCatalog.groups.count)
        #expect(groups.reduce(0) { $0 + $1.scenarios.count } == ScenarioCatalog.all.count)
    }

    @Test func filterMatchesNameFileUseCaseAndTheme() {
        // Name: the two OAuth mocks. "oauth" alone also catches the secrets
        // rotation scenario, which is the point of a full-text filter.
        #expect(ScenarioCatalog.filtered("oauth mock").reduce(0) { $0 + $1.scenarios.count } == 2)
        #expect(ScenarioCatalog.filtered("oauth").reduce(0) { $0 + $1.scenarios.count } == 3)

        // File: a full file name narrows to one row.
        let byFile = ScenarioCatalog.filtered("federation-mesh.yaml")
        #expect(byFile.count == 1)
        #expect(byFile.first?.scenarios.first?.name == "Federation mesh")

        // Use case: "quorum" appears in the worker-pool description.
        #expect(ScenarioCatalog.filtered("quorum").first?.scenarios.first?.file == "federation-pool.yaml")

        // Theme title: "warroom" selects the whole incident group.
        let byTheme = ScenarioCatalog.filtered("warroom")
        #expect(byTheme.count == 1)
        #expect(byTheme.first?.scenarios.count == 6)
    }

    @Test func filterIsCaseInsensitiveAndTrimsWhitespace() {
        #expect(ScenarioCatalog.filtered("  FEDERATION  ").first?.theme == .federation)
        #expect(ScenarioCatalog.filtered("Tuner").first?.theme == .deployment)
    }

    @Test func filterDropsNonMatches() {
        #expect(ScenarioCatalog.filtered("no-such-scenario").isEmpty)
    }

    @Test func generatedAndHarnessConfigsAreOmitted() {
        let files = Set(ScenarioCatalog.all.map(\.file))
        #expect(!files.contains("mcp-add-meta-20260408-045454.yaml"))
        #expect(!files.contains("dev/config.yaml"))
        #expect(!files.contains("dev/1.yaml"))
        #expect(!files.contains("qa/config.yaml"))
    }

    @Test func provenanceIsRecorded() {
        #expect(ScenarioCatalog.sourceCommit.count == 7)
        #expect(!ScenarioCatalog.sourceDate.isEmpty)
    }
}
