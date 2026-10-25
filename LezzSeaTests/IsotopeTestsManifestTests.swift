//
//  IsotopeTestsManifestTests.swift
//  LezzSeaTests
//
//  The manifest is evidence, so the decoder must distinguish three things:
//  malformed/unsupported input (throw), a failing suite (decode and show it),
//  and a passing suite. A decoder that threw on `ok: false` would hide the
//  exact failure the app exists to display.
//

import Foundation
import Testing
@testable import LezzSea

struct IsotopeTestsManifestTests {

    @Test func decodesTheCurrentShape() throws {
        let manifest = try IsotopeTestsManifestLoader.decode(fixture())

        #expect(manifest.isSupported)
        #expect(manifest.subject == "kb")
        #expect(manifest.tests.count == 1)
        #expect(manifest.tests[0].name == "handshake-tumble")
        #expect(manifest.tests[0].isotope == "5nhjeum3xz39rkh805OeB8TQheaM3mYEFowUE-3c9Jo")
        #expect(manifest.tests[0].clean)
        #expect(manifest.behavior.verifySecurity?.ok == true)
        #expect(manifest.behavior.negotiate["openttd"]?.ok == true)
        #expect(manifest.isPassing)
        #expect(manifest.summary == "1/1 clean · 1/1 negotiate · ok")
    }

    @Test func rejectsAnUnknownSchema() throws {
        do {
            _ = try IsotopeTestsManifestLoader.decode(fixture(schema: "lezzsea.isotope-tests/v2"))
            Issue.record("an unknown schema decoded")
        } catch let error as IsotopeTestsManifestError {
            #expect(error == .unsupportedSchema("lezzsea.isotope-tests/v2"))
        }
    }

    @Test func aFailingSuiteIsDecodedAndShown() throws {
        let manifest = try IsotopeTestsManifestLoader.decode(
            fixture(ok: false, clean: false, scanOK: false, negotiateOK: false)
        )

        #expect(!manifest.isPassing)
        #expect(manifest.failedTests.map(\.name) == ["handshake-tumble"])
        #expect(manifest.failedNegotiations == ["openttd"])
        #expect(Set(manifest.failedBehavior) == [
            "verify_empty_gate",
            "verify_empty_proxy",
            "verify_security",
            "verify_rotations",
        ])
        #expect(manifest.summary == "0/1 clean · 0/1 negotiate · failing")
    }

    @Test func aMissingNegotiateMapIsEmpty() throws {
        let manifest = try IsotopeTestsManifestLoader.decode(fixture(includeNegotiate: false))

        #expect(manifest.behavior.negotiate.isEmpty)
        #expect(manifest.failedNegotiations.isEmpty)
        #expect(manifest.isPassing)
    }

    @Test func optionalFieldsMayBeAbsentOrNull() throws {
        let manifest = try IsotopeTestsManifestLoader.decode(
            fixture(clean: true, includeOptional: false, isotopeNull: true)
        )

        #expect(manifest.validator == nil)
        #expect(manifest.brine == nil)
        #expect(manifest.error == nil)
        #expect(manifest.tests[0].isotope == nil)
    }

    @Test func unknownKeysAreIgnored() throws {
        let manifest = try IsotopeTestsManifestLoader.decode(
            fixture(extra: #", "future_field": {"version": 2}"#)
        )

        #expect(manifest.isPassing)
        #expect(manifest.tests.count == 1)
    }

    @Test func loaderReadsAManifestFromDisk() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("isotope-tests-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        try fixture().write(to: url)

        let manifest = try IsotopeTestsManifestLoader.load(from: url)
        #expect(manifest.isPassing)
        #expect(manifest.behavior.negotiate["openttd"]?.exit == 0)
    }

    // MARK: - Fixture

    private func fixture(
        schema: String = IsotopeTestsManifest.schema,
        ok: Bool = true,
        clean: Bool = true,
        scanOK: Bool = true,
        negotiateOK: Bool = true,
        includeNegotiate: Bool = true,
        includeOptional: Bool = true,
        isotopeNull: Bool = false,
        extra: String = ""
    ) -> Data {
        let isotope = isotopeNull ? "null" : #""5nhjeum3xz39rkh805OeB8TQheaM3mYEFowUE-3c9Jo""#
        let negotiate = includeNegotiate
            ? #", "negotiate": {"openttd": {"ok": \#(negotiateOK), "exit": 0, "output_tail": "ok"}}"#
            : ""
        let optional = includeOptional
            ? #", "validator": "validator", "brine": "brine", "error": """#
            : ""
        let json = """
        {
          "schema": "\(schema)",
          "suite": "lezzsea.isotope-tests",
          "subject": "kb",
          "generated_at": "2026-10-25T00:00:00Z",
          "tests": [
            {
              "name": "handshake-tumble",
              "file": "features/handshake-tumble.feature",
              "isotope": \(isotope),
              "clean": \(clean),
              "exit": 0,
              "output_tail": "clean"
            }
          ],
          "behavior": {
            "verify_empty_gate": {"ok": \(scanOK), "exit": 0, "output_tail": "ok"},
            "verify_empty_proxy": {"ok": \(scanOK), "exit": 0, "output_tail": "ok"},
            "verify_security": {"ok": \(scanOK), "exit": 0, "output_tail": "ok"},
            "verify_rotations": {"ok": \(scanOK), "exit": 0, "output_tail": "ok"}
            \(negotiate)
          },
          "ok": \(ok)\(optional)\(extra)
        }
        """
        return Data(json.utf8)
    }
}
