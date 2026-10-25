//
//  LabCluster.swift
//  LezzSea
//
//  One launched scenario: a cluster of smoke-alarm processes that share a
//  federation root and an isotope agreement.
//
//  The cluster is described on disk by `cluster.json`, in the same directory
//  the members' configs and state live in. That file is the contract between
//  the app's launcher and anything else that starts a lab cluster — a test
//  script can write it, and the app will display and stop that cluster as if
//  it had launched it. Nothing in the file records which side started it.
//

import Foundation

struct LabCluster: Codable, Identifiable, Hashable, Sendable {
    let scenarioID: String
    let name: String
    let slug: String
    /// The shared federation identity. Peers announcing the same value are
    /// trusted by construction; that is the isotope agreement.
    let clusterID: String?
    /// The first port of the federation slot range — the root a follower
    /// announces at, and where the leader serves `/membership`.
    let rootPort: Int?
    let startedAt: Date
    let members: [LabMember]

    var id: String { slug }

    var membershipURL: URL? {
        guard let rootPort else { return nil }
        return URL(string: "http://127.0.0.1:\(rootPort)/membership")
    }

    var rootLabel: String? {
        guard let rootPort else { return nil }
        return ":\(rootPort)"
    }

    func member(for isotope: String) -> LabMember? {
        members.first { $0.isotope == isotope }
    }

    /// A port to try before mDNS answers. The preferred port is what the
    /// sample asked for; the first process to bind it usually keeps it.
    func preferredHealthPort(for isotope: String) -> Int? {
        member(for: isotope)?.preferredHealthPort
    }

    var launchCommand: String? {
        members.first.map { $0.launchCommand }
    }
}

struct LabMember: Codable, Identifiable, Hashable, Sendable {
    /// 1-based position in the launch. Also part of the isotope suffix.
    let index: Int
    /// The rotated service name: the mDNS instance name, and the name the
    /// alarm reports as its `service`.
    let isotope: String
    /// The health port the member's config asks for. Discovery is what says
    /// which port it actually bound.
    let preferredHealthPort: Int
    let configPath: String
    let pidPath: String
    let logPath: String
    let stateDir: String

    var id: String { isotope }

    var directory: URL {
        URL(fileURLWithPath: configPath).deletingLastPathComponent()
    }

    var launchCommand: String {
        "lezz run ocd-smoke-alarm serve --config=\(configPath) --mode=headless"
    }

    func healthURL(port: Int) -> URL {
        URL(string: "http://127.0.0.1:\(port)/status")!
    }
}

// MARK: - Federation membership

/// The introducer's view at `<root>/membership`. Only the fields the app acts
/// on are decoded; the alarm may add more.
struct FederationMembership: Decodable, Sendable {
    struct Record: Decodable, Sendable {
        let id: String
        let serviceName: String?
        let port: Int?
        let role: String?
        let clusterID: String?

        enum CodingKeys: String, CodingKey {
            case id
            case serviceName = "service_name"
            case port
            case role
            case clusterID = "cluster_id"
        }
    }

    let selfRecord: Record
    let peers: [Record]

    enum CodingKeys: String, CodingKey {
        case selfRecord = "self"
        case peers
    }

    var all: [Record] { [selfRecord] + peers }

    var serviceNames: Set<String> {
        Set(all.compactMap(\.serviceName))
    }

    var clusterIDs: Set<String> {
        Set(all.compactMap(\.clusterID))
    }

    var leader: Record { selfRecord }

    var hasAgreement: Bool { clusterIDs.count == 1 }
}

/// A smoke-alarm `/status` document, reduced to what proves identity.
struct AlarmStatus: Decodable, Sendable {
    let live: Bool?
    let service: String?
}
