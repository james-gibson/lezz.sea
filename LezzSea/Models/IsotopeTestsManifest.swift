//
//  IsotopeTestsManifest.swift
//  LezzSea
//
//  The decoder for the KB suite's `lezzsea.isotope-tests/v1` manifest.
//
//  LezzSea is the observation layer; the KB cluster is the subject. The manifest
//  is the evidence a run leaves behind: the isotope identity of every canon test,
//  the result of every live scan, and the per-scope negotiation outcomes. This
//  file is deliberately pure data plus decoding — no AppModel, no network, no
//  file access in the model itself — so the same shapes can be reused by a CLI
//  or a future panel.
//
//  A failing manifest is not a decoding failure. The app must be able to show
//  which test failed and which scan is red, so `ok: false` decodes normally;
//  only an unknown schema or malformed JSON is an error.
//

import Foundation

struct IsotopeTestsManifest: Decodable, Equatable, Sendable {

    /// The only schema this decoder accepts.
    static let schema = "lezzsea.isotope-tests/v1"

    let schema: String
    let suite: String
    let subject: String
    let generatedAt: String
    let validator: String?
    let brine: String?
    let tests: [CanonTest]
    let behavior: Behavior
    let ok: Bool
    let error: String?

    /// One isotope test: the feature file, its derived identity, and its canon
    /// result. `isotope` is optional because a malformed feature can fail before
    /// the canon derives one.
    struct CanonTest: Decodable, Equatable, Identifiable, Sendable {
        let name: String
        let file: String
        let isotope: String?
        let clean: Bool
        let exit: Int
        let outputTail: String?

        var id: String { name }
    }

    /// The executable scans. The four named scans are the stable suite; the
    /// negotiate map is one result per running scope.
    struct Behavior: Decodable, Equatable, Sendable {
        let verifyEmptyGate: ScanResult?
        let verifyEmptyProxy: ScanResult?
        let verifySecurity: ScanResult?
        let verifyRotations: ScanResult?
        let negotiate: [String: ScanResult]

        enum CodingKeys: String, CodingKey {
            case verifyEmptyGate
            case verifyEmptyProxy
            case verifySecurity
            case verifyRotations
            case negotiate
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            verifyEmptyGate = try container.decodeIfPresent(ScanResult.self, forKey: .verifyEmptyGate)
            verifyEmptyProxy = try container.decodeIfPresent(ScanResult.self, forKey: .verifyEmptyProxy)
            verifySecurity = try container.decodeIfPresent(ScanResult.self, forKey: .verifySecurity)
            verifyRotations = try container.decodeIfPresent(ScanResult.self, forKey: .verifyRotations)
            negotiate = try container.decodeIfPresent([String: ScanResult].self, forKey: .negotiate) ?? [:]
        }
    }

    /// One scan result. `output_tail` is the last part of the command's output,
    /// kept for the failing case; it is not a secret.
    struct ScanResult: Decodable, Equatable, Sendable {
        let ok: Bool
        let exit: Int
        let outputTail: String?
    }

    /// True when the manifest's schema is the one this app understands.
    var isSupported: Bool { schema == Self.schema }

    /// True only when the suite says `ok` and every local check agrees with it.
    /// The app renders `ok` from the manifest, but a decoder that silently
    /// accepted `ok: true` beside a failing test would be lying about the
    /// evidence.
    var isPassing: Bool {
        ok && failedTests.isEmpty && failedBehavior.isEmpty && failedNegotiations.isEmpty
    }

    var cleanCount: Int { tests.filter(\.clean).count }

    var failedTests: [CanonTest] { tests.filter { !$0.clean } }

    /// The named scans that are not `ok`, in suite order. Negotiate is separate
    /// because it has one result per scope.
    var failedBehavior: [String] {
        [
            ("verify_empty_gate", behavior.verifyEmptyGate),
            ("verify_empty_proxy", behavior.verifyEmptyProxy),
            ("verify_security", behavior.verifySecurity),
            ("verify_rotations", behavior.verifyRotations),
        ].compactMap { name, result in
            guard let result, !result.ok else { return nil }
            return name
        }
    }

    var failedNegotiations: [String] {
        behavior.negotiate
            .filter { !$0.value.ok }
            .keys
            .sorted()
    }

    /// A compact line for a list or a status item. Failure details stay in the
    /// arrays above so the UI can show the exact test or scan.
    var summary: String {
        let canon = "\(cleanCount)/\(tests.count) clean"
        let negotiate = "\(behavior.negotiate.count - failedNegotiations.count)/\(behavior.negotiate.count) negotiate"
        return "\(canon) · \(negotiate) · \(isPassing ? "ok" : "failing")"
    }
}

enum IsotopeTestsManifestError: LocalizedError, Equatable {
    case unsupportedSchema(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedSchema(let schema):
            "The isotope-test manifest uses \(schema), not \(IsotopeTestsManifest.schema)."
        }
    }
}

enum IsotopeTestsManifestLoader {

    /// Decode and check the schema. A failing suite (`ok: false`) is returned,
    /// not thrown: the caller needs the failures to display them.
    static func decode(_ data: Data) throws -> IsotopeTestsManifest {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let manifest = try decoder.decode(IsotopeTestsManifest.self, from: data)
        guard manifest.isSupported else {
            throw IsotopeTestsManifestError.unsupportedSchema(manifest.schema)
        }
        return manifest
    }

    /// Read a manifest from disk. The sandboxed app cannot open an arbitrary
    /// path; the Lab build or a CLI can, and a sandboxed caller should pass a
    /// security-scoped URL it already has access to.
    static func load(from url: URL) throws -> IsotopeTestsManifest {
        try decode(Data(contentsOf: url))
    }
}
