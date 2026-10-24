//
//  ScenarioConfigTests.swift
//  LezzSeaTests
//
//  The derived config is what makes a sample safe to run beside another one.
//  These tests pin the narrow rewrite: only the alarm's own listeners and the
//  self-references to those ports move; a target on some other localhost port
//  is left alone.
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
      - id: "unrelated"
        endpoint: "http://localhost:19301/mcp"
      - id: "any"
        endpoint: "http://0.0.0.0:18088/healthz"

    # a comment mentioning localhost:18088
    """

    private var directory: URL {
        URL(fileURLWithPath: "/tmp/lezzsea-scenario-test", isDirectory: true)
    }

    @Test func remapsOnlyTheAlarmsOwnPorts() throws {
        let derived = try ScenarioConfig.derive(
            source: sample,
            instanceDirectory: directory,
            offset: 1_000
        )

        #expect(derived.healthPort == 19_088)
        #expect(derived.ports.contains(19_088))
        #expect(derived.ports.contains(19_089))
        #expect(derived.ports.contains(9_877))
        #expect(derived.ports.contains(6_100))
        #expect(derived.ports.contains(6_103))

        #expect(derived.text.contains("listen_addr: \"127.0.0.1:19088\""))
        #expect(derived.text.contains("listen_addr: \"127.0.0.1:19089\""))
        #expect(derived.text.contains("listen_addr: \"127.0.0.1:9877\""))
        #expect(derived.text.contains("base_port: 6100"))
        #expect(derived.text.contains("max_port: 6103"))

        // A self-target follows the listener.
        #expect(derived.text.contains("http://127.0.0.1:19089/mcp"))
        // An unrelated localhost service does not.
        #expect(derived.text.contains("http://localhost:19301/mcp"))
        // The all-interface self-target is pinned to loopback.
        #expect(derived.text.contains("http://127.0.0.1:19088/healthz"))
    }

    @Test func statePathsAreAbsoluteAndPerInstance() throws {
        let derived = try ScenarioConfig.derive(
            source: sample,
            instanceDirectory: directory,
            offset: 0
        )

        #expect(derived.text.contains("state_dir: \"\(directory.path)/state\""))
        #expect(derived.text.contains("lock_file: \"\(directory.path)/ocd-smoke-alarm.pid\""))
        #expect(derived.text.contains("baseline_file: \"\(directory.path)/state/known-good.json\""))
        #expect(!derived.text.contains("state_dir: \"./state\""))
    }

    @Test func ephemeralPortsAreNotRemapped() throws {
        let ephemeral = sample.replacingOccurrences(
            of: "listen_addr: \":18089\"",
            with: "listen_addr: \":0\""
        )
        let derived = try ScenarioConfig.derive(
            source: ephemeral,
            instanceDirectory: directory,
            offset: 1_000
        )

        #expect(derived.text.contains("listen_addr: \":0\""))
        #expect(!derived.ports.contains(1_000))
    }

    @Test func commentsFollowTheRemap() throws {
        let derived = try ScenarioConfig.derive(
            source: sample,
            instanceDirectory: directory,
            offset: 1_000
        )
        #expect(derived.text.contains("# a comment mentioning 127.0.0.1:19088"))
    }

    @Test func missingHealthListenerFails() {
        let noHealth = sample.replacingOccurrences(of: "listen_addr: \"localhost:18088\"", with: "enabled: false")
        #expect(throws: ScenarioConfig.DeriveError.self) {
            try ScenarioConfig.derive(source: noHealth, instanceDirectory: directory, offset: 0)
        }
    }

    @Test func missingRuntimeKeyFails() {
        let noLock = sample.replacingOccurrences(of: "  lock_file: \"/tmp/test.lock\"\n", with: "")
        #expect(throws: ScenarioConfig.DeriveError.self) {
            try ScenarioConfig.derive(source: noLock, instanceDirectory: directory, offset: 0)
        }
    }

    @Test func offsetThatOverflowsAPortFails() {
        let high = sample.replacingOccurrences(of: "localhost:18088", with: "localhost:64000")
        #expect(throws: ScenarioConfig.DeriveError.self) {
            try ScenarioConfig.derive(source: high, instanceDirectory: directory, offset: 2_000)
        }
    }
}
