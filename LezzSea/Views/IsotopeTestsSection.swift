//
//  IsotopeTestsSection.swift
//  LezzSea
//
//  The live half of the Isotopes pane: the manifest the KB suite leaves behind,
//  decoded and shown next to the static smoke-alarm chart.
//
//  The chart is static and needs no cluster. This section is evidence from a
//  run: the isotope identities, the scan outcomes, and the per-scope
//  negotiation result. It loads a user-selected JSON file; the sandboxed build
//  has user-selected read-only access, and the Lab build can read it directly.
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct IsotopeTestsSection: View {

    @State private var manifest: IsotopeTestsManifest?
    @State private var loadError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header

            if let manifest {
                content(manifest)
            } else {
                emptyState
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.bar)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Isotope tests")
        .accessibilityIdentifier("isotopes.tests.root")
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            Label("Isotope tests", systemImage: "checkmark.seal")
                .font(.headline)

            Text("LezzSea's live scans of the KB cluster.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Spacer(minLength: 8)

            Button("Load…", action: chooseManifest)
                .help("Load an isotope-tests manifest (build/isotope-tests.json)")
                .accessibilityIdentifier("isotopes.tests.load")
        }
    }

    // MARK: - Loaded

    @ViewBuilder
    private func content(_ manifest: IsotopeTestsManifest) -> some View {
        HStack(spacing: 8) {
            Image(systemName: manifest.isPassing ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(manifest.isPassing ? Color.green : Color.red)
                .accessibilityHidden(true)

            Text(manifest.summary)
                .font(.callout.monospacedDigit())
                .accessibilityIdentifier("isotopes.tests.summary")

            Text("subject \(manifest.subject)")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer(minLength: 8)

            Text(manifest.generatedAt)
                .font(.caption2.monospaced())
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .truncationMode(.middle)
                .help(manifest.generatedAt)
        }

        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(manifest.tests) { test in
                    testChip(test)
                }

                ForEach(scans(manifest)) { scan in
                    scanChip(scan.name, result: scan.result)
                }

                negotiateChip(manifest)
            }
            .padding(.vertical, 1)
        }
        .accessibilityIdentifier("isotopes.tests.rows")

        if !manifest.isPassing {
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(failures(manifest), id: \.self) { failure in
                        Label(failure, systemImage: "xmark.octagon.fill")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 54)
            .accessibilityIdentifier("isotopes.tests.failures")
        }
    }

    private func testChip(_ test: IsotopeTestsManifest.CanonTest) -> some View {
        HStack(spacing: 5) {
            Image(systemName: test.clean ? "checkmark" : "xmark")
                .font(.caption2.weight(.bold))
                .foregroundStyle(test.clean ? Color.green : Color.red)
            VStack(alignment: .leading, spacing: 0) {
                Text(test.name)
                    .font(.caption)
                    .lineLimit(1)
                Text(isotopePrefix(test.isotope))
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(chipBackground(test.clean))
        .overlay(chipBorder(test.clean))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "\(test.name), \(test.clean ? "clean" : "failed"), isotope \(test.isotope ?? "not derived")"
        )
    }

    private func scanChip(_ name: String, result: IsotopeTestsManifest.ScanResult?) -> some View {
        let ok = result?.ok ?? false
        return HStack(spacing: 5) {
            Image(systemName: ok ? "checkmark" : "xmark")
                .font(.caption2.weight(.bold))
                .foregroundStyle(ok ? Color.green : Color.red)
            Text(name)
                .font(.caption)
                .lineLimit(1)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(chipBackground(ok))
        .overlay(chipBorder(ok))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(name), \(ok ? "ok" : "failed")")
    }

    private func chipBackground(_ ok: Bool) -> some View {
        RoundedRectangle(cornerRadius: 6)
            .fill((ok ? Color.green : Color.red).opacity(0.08))
    }

    private func chipBorder(_ ok: Bool) -> some View {
        RoundedRectangle(cornerRadius: 6)
            .stroke((ok ? Color.green : Color.red).opacity(0.28), lineWidth: 1)
    }

    private func isotopePrefix(_ isotope: String?) -> String {
        guard let isotope, !isotope.isEmpty else { return "—" }
        return isotope.count > 10 ? "\(isotope.prefix(10))…" : isotope
    }

    private struct Scan: Identifiable {
        let name: String
        let result: IsotopeTestsManifest.ScanResult?
        var id: String { name }
    }

    private func scans(_ manifest: IsotopeTestsManifest) -> [Scan] {
        [
            Scan(name: "empty gate", result: manifest.behavior.verifyEmptyGate),
            Scan(name: "empty proxy", result: manifest.behavior.verifyEmptyProxy),
            Scan(name: "security", result: manifest.behavior.verifySecurity),
            Scan(name: "rotation", result: manifest.behavior.verifyRotations),
        ]
    }

    private func negotiateChip(_ manifest: IsotopeTestsManifest) -> some View {
        let negotiated = manifest.behavior.negotiate.count - manifest.failedNegotiations.count
        return scanChip(
            "negotiate \(negotiated)/\(manifest.behavior.negotiate.count)",
            result: IsotopeTestsManifest.ScanResult(
                ok: manifest.failedNegotiations.isEmpty,
                exit: manifest.failedNegotiations.isEmpty ? 0 : 1,
                outputTail: nil
            )
        )
    }

    private func failures(_ manifest: IsotopeTestsManifest) -> [String] {
        var failures = manifest.failedTests.map { "test \($0.name)" }
        failures += manifest.failedBehavior.map { "scan \($0)" }
        failures += manifest.failedNegotiations.map { "negotiate \($0)" }
        if let error = manifest.error, !error.isEmpty {
            failures.append("manifest: \(error)")
        }
        if failures.isEmpty, manifest.ok == false {
            failures.append("manifest reports a failure")
        }
        return failures
    }

    // MARK: - Empty / error

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(loadError ?? "No manifest loaded.")
                .font(.caption)
                .foregroundStyle(loadError == nil ? Color.secondary : Color.red)
                .accessibilityIdentifier("isotopes.tests.message")

            Text("Run scripts/isotope-tests.sh, then load build/isotope-tests.json.")
                .font(.caption2.monospaced())
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: - Load

    private func chooseManifest() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.message = "Choose an isotope-tests manifest (build/isotope-tests.json)"
        panel.prompt = "Load"
        guard panel.runModal() == .OK, let url = panel.url else { return }

        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        do {
            manifest = try IsotopeTestsManifestLoader.load(from: url)
            loadError = nil
        } catch {
            manifest = nil
            loadError = error.localizedDescription
        }
    }
}

#Preview("Isotope tests") {
    IsotopeTestsSection()
        .frame(width: 820, height: 150)
}
