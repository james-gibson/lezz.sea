//
//  ScenarioConfigTests.swift
//  LezzSeaTests
//
//  The derived config is what makes a sample safe to run beside another one.
//  These tests pin the narrow rewrite: state moves to an absolute per-instance
//  directory, the isotope name rotates, discovery switches on and the cluster
//  agreement is supplied. Ports are deliberately left alone — the alarm
//  self-negotiates them.
//

import Foundation
import Testing
@testable import LezzSea

struct ScenarioConfigTests {

    private let sample = """
    version: "1"

    service:
      name: "test"
      mode: "foreground"

    health:
      enabled: true
      listen_addr: "localhost:18088"

    runtime:
      lock_file: "/tmp/test.lock"
      state_dir: "./state"
      baseline_file: "./state/known-good.json"

    hosted:
      enabled: true
      listen_addr: ":18089"
      endpoints:
        mcp: "/mcp"

    auth:
      enabled: true
      listen_addr: "0.0.0.0:8877"

    federation:
      enabled: true
      base_port: 5100
      max_port: 5103 # supports 5100-5103

    targets:
      - id: "self"
        endpoint: "http://localhost:18089/mcp"

    # a comment mentioning localhost:18088
    """

    private var directory: URL {
        URL(fileURLWithPath: "/tmp/lezzsea-scenario-test", isDirectory: true)
    }

    private func derive(
        _ source: String? = nil,
        index: Int = 2
    ) throws -> ScenarioConfig.Derived {
        try ScenarioConfig.derive(
            source: source ?? sample,
            instanceDirectory: directory,
            slug: "test",
            index: index
        )
    }

    @Test func portsAreNotMoved() throws {
        let derived = try derive()

        #expect(derived.preferredHealthPort == 18_088)
        #expect(derived.rootPort == 5_100)
        #expect(derived.text.contains("listen_addr: \"localhost:18088\""))
        #expect(derived.text.contains("listen_addr: \":18089\""))
        #expect(derived.text.contains("listen_addr: \"0.0.0.0:8877\""))
        #expect(derived.text.contains("base_port: 5100"))
        #expect(derived.text.contains("max_port: 5103"))
        #expect(derived.text.contains("http://localhost:18089/mcp"))
    }

    @Test func selfNegotiatingPortsStaySelfNegotiating() throws {
        let ephemeral = sample.replacingOccurrences(
            of: "listen_addr: \":18089\"",
            with: "listen_addr: \":0\""
        )
        let derived = try derive(ephemeral)
        #expect(derived.text.contains("listen_addr: \":0\""))
    }

    @Test func isotopeNameIsRotatedPerInstance() throws {
        let first = try derive(index: 1)
        let second = try derive(index: 2)

        #expect(first.isotope == "test-test-1")
        #expect(second.isotope == "test-test-2")
        #expect(first.text.contains("name: \"test-test-1\""))
        #expect(second.text.contains("name: \"test-test-2\""))
    }

    @Test func discoveryIsTurnedOnWithTheRotatedName() throws {
        let derived = try derive()

        #expect(derived.text.contains("tuner:"))
        #expect(derived.text.contains("advertise: true"))
        #expect(derived.text.contains("service_type: \"_smoke-alarm._tcp\""))
    }

    @Test func anExistingTunerBlockIsRewrittenNotDuplicated() throws {
        let withTuner = sample + "\n" + """
            tuner:
              enabled: false
              advertise: false
              service_type: "_other._tcp"
            """
        let derived = try derive(withTuner)

        #expect(derived.text.components(separatedBy: "tuner:").count == 2)
        #expect(derived.text.contains("advertise: true"))
        #expect(!derived.text.contains("advertise: false"))
        #expect(!derived.text.contains("_other._tcp"))
    }

    @Test func theAgreementIsSuppliedWhenTheSampleHasNone() throws {
        let derived = try derive()

        #expect(derived.clusterID == "lezzsea-test")
        #expect(derived.text.contains("cluster_id: \"lezzsea-test\""))
        #expect(derived.text.components(separatedBy: "cluster_id:").count == 2)
    }

    @Test func aDeclaredAgreementIsKept() throws {
        let declared = sample.replacingOccurrences(
            of: "  base_port: 5100",
            with: "  cluster_id: \"mesh-sample\"\n  base_port: 5100"
        )
        let derived = try derive(declared)

        #expect(derived.clusterID == "mesh-sample")
        #expect(derived.text.contains("cluster_id: \"mesh-sample\""))
        #expect(!derived.text.contains("lezzsea-test"))
    }

    @Test func anEmptyAgreementIsFilledRatherThanDuplicated() throws {
        let empty = sample.replacingOccurrences(
            of: "  base_port: 5100",
            with: "  cluster_id: \"\"\n  base_port: 5100"
        )
        let derived = try derive(empty)

        #expect(derived.clusterID == "lezzsea-test")
        #expect(derived.text.components(separatedBy: "cluster_id:").count == 2)
    }

    @Test func statePathsAreAbsoluteAndPerInstance() throws {
        let derived = try derive()

        #expect(derived.text.contains("state_dir: \"\(directory.path)/state\""))
        #expect(derived.text.contains("lock_file: \"\(directory.path)/ocd-smoke-alarm.pid\""))
        #expect(derived.text.contains("baseline_file: \"\(directory.path)/state/known-good.json\""))
        #expect(!derived.text.contains("state_dir: \"./state\""))
        #expect(!derived.text.contains("/tmp/test.lock"))
    }

    @Test func commentsAreLeftAlone() throws {
        let derived = try derive()
        #expect(derived.text.contains("# a comment mentioning localhost:18088"))
        #expect(derived.text.contains("# supports 5100-5103"))
    }

    @Test func aNonFederationSampleHasNoRoot() throws {
        let noFederation = sample.components(separatedBy: "federation:").first ?? sample
        let derived = try derive(noFederation)

        #expect(derived.rootPort == nil)
        #expect(derived.clusterID == nil)
        #expect(!derived.text.contains("cluster_id:"))
    }

    @Test func missingHealthListenerFails() {
        let noHealth = sample.replacingOccurrences(
            of: "listen_addr: \"localhost:18088\"",
            with: "enabled: false"
        )
        #expect(throws: ScenarioConfig.DeriveError.self) {
            try derive(noHealth)
        }
    }

    @Test func missingServiceNameFails() {
        let noName = sample.replacingOccurrences(of: "  name: \"test\"\n", with: "")
        #expect(throws: ScenarioConfig.DeriveError.self) {
            try derive(noName)
        }
    }

    @Test func missingRuntimeKeyFails() {
        let noLock = sample.replacingOccurrences(of: "  lock_file: \"/tmp/test.lock\"\n", with: "")
        #expect(throws: ScenarioConfig.DeriveError.self) {
            try derive(noLock)
        }
    }
}
