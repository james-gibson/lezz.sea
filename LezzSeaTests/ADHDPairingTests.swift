//
//  ADHDPairingTests.swift
//  LezzSeaTests
//
//  The paired adhd's config is derived from ports that answered, so these
//  tests pin its shape rather than any network behaviour: one `smoke_alarm`
//  entry per member, the MCP server on the allocated port, and the Gherkin glob
//  only when the checkout actually has a features directory.
//

import Foundation
import Testing
@testable import LezzSea

struct ADHDPairingTests {

    @Test func oneMemberIsNamedAfterTheScenario() {
        let text = ADHDPairing.config(
            slug: "stdio-mcp-strict",
            healthPorts: [18_188],
            mcpPort: 9_190,
            gherkinDirectory: nil
        )

        #expect(text == """
        mcp_server:
          enabled: true
          addr: "127.0.0.1:9190"
        smoke_alarm:
          - name: "stdio-mcp-strict"
            endpoint: "http://127.0.0.1:18188"
            interval: 10s

        """)
    }

    @Test func everyMemberGetsAnEntryInOrder() {
        let text = ADHDPairing.config(
            slug: "federation-mesh",
            healthPorts: [18_088, 18_089, 18_090],
            mcpPort: 9_201,
            gherkinDirectory: nil
        )

        #expect(text.components(separatedBy: "  - name:").count - 1 == 3)
        #expect(text.contains("name: \"federation-mesh-1\""))
        #expect(text.contains("name: \"federation-mesh-2\""))
        #expect(text.contains("name: \"federation-mesh-3\""))
        #expect(text.contains("endpoint: \"http://127.0.0.1:18090\""))
        #expect(text.contains("addr: \"127.0.0.1:9201\""))
        #expect(!text.contains("features:"))
    }

    @Test func theCheckoutGherkinIsOnlyReferencedWhenItExists() {
        let directory = URL(fileURLWithPath: "/lab/smoke-alarm/features", isDirectory: true)
        let text = ADHDPairing.config(
            slug: "health",
            healthPorts: [18_088],
            mcpPort: 9_190,
            gherkinDirectory: directory
        )

        #expect(text.contains("features:"))
        #expect(text.contains("name: ocd-smoke-alarm"))
        #expect(text.contains("gherkin_files:"))
        #expect(text.contains("- \"\(directory.path)/*.feature\""))
        #expect(text.contains("endpoint: \"http://127.0.0.1:18088/status\""))
    }

    @Test func thePortRangeIsTheScriptsRange() {
        #expect(ADHDPairing.portRange == 9_190...9_289)
        if let port = ADHDPairing.freePort() {
            #expect(ADHDPairing.portRange.contains(port))
        }
    }
}
