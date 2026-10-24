//
//  LabClusterTests.swift
//  LezzSeaTests
//
//  `cluster.json` is the contract between the app's launcher and any other
//  launcher — the verification script writes the same shape. These tests pin
//  that shape, the membership decoding that decides whether a cluster is
//  whole, and the multi-member adhd block.
//

import Foundation
import Testing
@testable import LezzSea

struct LabClusterTests {

    private let json = """
    {
      "scenarioID": "federation-mesh.yaml",
      "name": "Federation mesh",
      "slug": "federation-mesh",
      "clusterID": "federation-mesh-sample",
      "rootPort": 5100,
      "startedAt": "2026-10-24T05:27:46Z",
      "members": [
        {
          "index": 1,
          "isotope": "ocd-smoke-alarm-federation-mesh-1",
          "preferredHealthPort": 18088,
          "configPath": "/tmp/lab/member-1/config.yaml",
          "pidPath": "/tmp/lab/member-1/ocd-smoke-alarm.pid",
          "logPath": "/tmp/lab/member-1/alarm.log",
          "stateDir": "/tmp/lab/member-1/state"
        },
        {
          "index": 2,
          "isotope": "ocd-smoke-alarm-federation-mesh-2",
          "preferredHealthPort": 18088,
          "configPath": "/tmp/lab/member-2/config.yaml",
          "pidPath": "/tmp/lab/member-2/ocd-smoke-alarm.pid",
          "logPath": "/tmp/lab/member-2/alarm.log",
          "stateDir": "/tmp/lab/member-2/state"
        }
      ]
    }
    """

    private var cluster: LabCluster {
        get throws {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(LabCluster.self, from: Data(json.utf8))
        }
    }

    @Test func decodesTheOnDiskContract() throws {
        let cluster = try cluster

        #expect(cluster.id == "federation-mesh")
        #expect(cluster.clusterID == "federation-mesh-sample")
        #expect(cluster.rootPort == 5_100)
        #expect(cluster.rootLabel == ":5100")
        #expect(cluster.membershipURL?.absoluteString == "http://127.0.0.1:5100/membership")
        #expect(cluster.members.count == 2)
        #expect(cluster.members[1].isotope == "ocd-smoke-alarm-federation-mesh-2")
        #expect(cluster.members[0].healthURL(port: 18_089).absoluteString == "http://127.0.0.1:18089/status")
    }

    @Test func aMemberIsFoundByIsotopeNotByPort() throws {
        let cluster = try cluster
        #expect(cluster.member(for: "ocd-smoke-alarm-federation-mesh-2")?.index == 2)
        #expect(cluster.member(for: "ocd-smoke-alarm-federation-mesh-3") == nil)
    }

    @Test func membershipDecodesTheRootView() throws {
        let json = """
        {
          "self": {
            "id": "531b71",
            "service_name": "ocd-smoke-alarm-federation-mesh-1",
            "port": 5100,
            "role": "introducer",
            "cluster_id": "federation-mesh-sample"
          },
          "peers": [
            {
              "id": "424a8e",
              "service_name": "ocd-smoke-alarm-federation-mesh-2",
              "port": 5101,
              "role": "follower",
              "cluster_id": "federation-mesh-sample"
            }
          ]
        }
        """

        let membership = try JSONDecoder().decode(
            FederationMembership.self,
            from: Data(json.utf8)
        )

        #expect(membership.leader.role == "introducer")
        #expect(membership.all.count == 2)
        #expect(membership.serviceNames == [
            "ocd-smoke-alarm-federation-mesh-1",
            "ocd-smoke-alarm-federation-mesh-2",
        ])
        #expect(membership.hasAgreement)
    }

    @Test func disagreeingPeersBreakTheAgreement() throws {
        let json = """
        {
          "self": {
            "id": "a",
            "service_name": "one",
            "port": 5100,
            "role": "introducer",
            "cluster_id": "cluster-a"
          },
          "peers": [
            { "id": "b", "service_name": "two", "port": 5101, "role": "follower", "cluster_id": "cluster-b" }
          ]
        }
        """

        let membership = try JSONDecoder().decode(
            FederationMembership.self,
            from: Data(json.utf8)
        )
        #expect(!membership.hasAgreement)
    }

    @Test func aSingleMemberBlockKeepsTheOldShape() {
        let scenario = ScenarioCatalog.all.first { $0.file == "stdio-mcp-strict.yaml" }!
        #expect(
            scenario.adhdSmokeAlarmBlock()
                == "smoke_alarm:\n  - name: \"stdio-mcp-strict\"\n    endpoint: \"http://127.0.0.1:18188\"\n    interval: 10s"
        )
    }

    @Test func everyDiscoveredPortGetsAnEntry() {
        let scenario = ScenarioCatalog.all.first { $0.file == "federation-mesh.yaml" }!
        let block = scenario.adhdSmokeAlarmBlock(healthPorts: [18_088, 18_089, 18_090])
        let lines = block.split(separator: "\n")

        #expect(lines.filter { $0.contains("name:") }.count == 3)
        #expect(block.contains("name: \"federation-mesh-1\""))
        #expect(block.contains("endpoint: \"http://127.0.0.1:18090\""))
        #expect(block.contains("name: \"federation-mesh-3\""))
    }

    @Test func aWholeClusterIsRunningAndALaggingOneIsPartial() throws {
        let cluster = try cluster

        let whole = FederationMembership(
            selfRecord: .init(id: "a", serviceName: "ocd-smoke-alarm-federation-mesh-1", port: 5100, role: "introducer", clusterID: "federation-mesh-sample"),
            peers: [.init(id: "b", serviceName: "ocd-smoke-alarm-federation-mesh-2", port: 5101, role: "follower", clusterID: "federation-mesh-sample")]
        )
        let (state, up) = ScenarioLab.evaluate(cluster: cluster, membership: whole)
        #expect(state == .running)
        #expect(up == 2)

        let lagging = FederationMembership(
            selfRecord: whole.selfRecord,
            peers: []
        )
        let (partialState, partialUp) = ScenarioLab.evaluate(cluster: cluster, membership: lagging)
        #expect(partialState == .partial)
        #expect(partialUp == 1)
    }

    @Test func anotherClustersRootOnOurPortIsNotOurCluster() throws {
        let cluster = try cluster

        // Every member is named, but under a different agreement: the port
        // belongs to another launch and must not be reported as ours.
        let foreign = FederationMembership(
            selfRecord: .init(id: "a", serviceName: "ocd-smoke-alarm-federation-mesh-1", port: 5100, role: "introducer", clusterID: "someone-else"),
            peers: [.init(id: "b", serviceName: "ocd-smoke-alarm-federation-mesh-2", port: 5101, role: "follower", clusterID: "someone-else")]
        )
        let (state, _) = ScenarioLab.evaluate(cluster: cluster, membership: foreign)
        #expect(state == .unreachable)
    }

    @Test func theMeshIsTheOnlyMultiProcessSample() {
        let multi = ScenarioCatalog.all.filter { $0.processes > 1 }
        #expect(multi.map(\.file) == ["federation-mesh.yaml"])
        #expect(multi.first?.processes == 3)
        #expect(!(multi.first?.isLaunchable ?? true))
        #expect(ScenarioCatalog.all.filter(\.isLaunchable).count == 26)
    }
}
