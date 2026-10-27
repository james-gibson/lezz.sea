//
//  LabChannelTests.swift
//  LezzSeaTests
//
//  The channel is a pipe, so the live end is exercised by launching the real
//  app from `lezz sea run`. These tests pin the wire shape: the app sends the
//  derived YAML as data (its container is TCC-protected from lezz.go), and a
//  reply carries the adhd endpoint and files lezz.go chose.
//

import Foundation
import Testing
@testable import LezzSea

struct LabChannelTests {

    @Test func aStartRequestCarriesTheConfigText() throws {
        var request = LabChannel.Request(want: "start", cluster: "stdio-mcp-strict")
        request.members = [
            LabChannel.Member(
                name: "member-1",
                config: "runtime:\n  state_dir: \"/lab/state\"\n"
            ),
        ]

        let data = try JSONEncoder().encode(request)
        let object = try #require(
            try JSONSerialization.jsonObject(with: data) as? [String: Any]
        )

        #expect(object["v"] as? Int == 1)
        #expect(object["type"] as? String == "request")
        #expect(object["want"] as? String == "start")
        #expect(object["cluster"] as? String == "stdio-mcp-strict")

        let members = try #require(object["members"] as? [[String: Any]])
        #expect(members.count == 1)
        #expect(members[0]["name"] as? String == "member-1")
        #expect((members[0]["config"] as? String)?.contains("state_dir") == true)
    }

    @Test func aStopRequestNamesOnlyTheCluster() throws {
        let request = LabChannel.Request(want: "stop", cluster: "stdio-mcp-strict")
        let data = try JSONEncoder().encode(request)
        let object = try #require(
            try JSONSerialization.jsonObject(with: data) as? [String: Any]
        )

        #expect(object["want"] as? String == "stop")
        #expect(object["cluster"] as? String == "stdio-mcp-strict")
        #expect(object["members"] == nil)
    }

    @Test func aReplyCarriesThePairedADHD() throws {
        let json = """
        {
          "v": 1,
          "type": "reply",
          "id": "7",
          "ok": true,
          "adhd": {
            "endpoint": "http://127.0.0.1:9190/mcp",
            "port": 9190,
            "configPath": "/lab/stdio-mcp-strict/adhd.yaml",
            "pidPath": "/lab/stdio-mcp-strict/adhd.pid"
          }
        }
        """
        let reply = try JSONDecoder().decode(LabChannel.Reply.self, from: Data(json.utf8))

        #expect(reply.ok == true)
        #expect(reply.adhd?.port == 9_190)
        #expect(reply.adhd?.endpoint == "http://127.0.0.1:9190/mcp")
        #expect(reply.adhd?.pidPath == "/lab/stdio-mcp-strict/adhd.pid")
    }

    @Test func aRefusalCarriesItsReason() throws {
        let json = """
        {"v":1,"type":"reply","id":"8","ok":false,"error":"config is outside the lab root"}
        """
        let reply = try JSONDecoder().decode(LabChannel.Reply.self, from: Data(json.utf8))

        #expect(reply.ok == false)
        #expect(reply.error == "config is outside the lab root")
    }
}
