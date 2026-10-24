//
//  BoundariesView.swift
//  LezzSea
//
//  The app's own constraints, on the screen: the invariant, the mechanism that
//  holds it, and what breaking it would mean. Static and self-contained — no
//  AppModel, no network, no persistence.
//
//  A refusal is rendered, never retained: keeping a log of what was blocked
//  would be a history, and a history is a join.
//

import SwiftUI

struct BoundariesView: View {

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(Boundaries.all) { boundary in
                        BoundaryRow(boundary: boundary)
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Divider()
            footer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Boundaries: the invariants the app depends on")
        .accessibilityIdentifier("boundaries.root")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Boundaries")
                .font(.title3.weight(.semibold))
            Text("What the app will not do, and what holds the line. The interface may never be more permissive than the protocol.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Every control maps to a protocol verb; every claim maps to a test. This view names tests — it does not run them, so it never reports them as passing.")
                .font(.caption2)
                .foregroundStyle(.secondary)

            Text("\(Boundaries.gaps.count) conformance gap\(Boundaries.gaps.count == 1 ? "" : "s") shown as debt, not as a pass. Source: smoke-alarm docs/adr/0020-the-boundary-is-the-interface.md.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
    }
}

private struct BoundaryRow: View {
    let boundary: Boundaries.Boundary

    var body: some View {
        // The evidence chip goes below the invariant rather than under a
        // `ViewThatFits` row: measuring two candidate rows here makes the
        // scroll view adopt a pathological ideal height on macOS, which then
        // inflates the whole split view. One layout, no measurement.
        HStack(alignment: .top, spacing: 10) {
            icon

            VStack(alignment: .leading, spacing: 4) {
                Text(boundary.invariant)
                    .font(.callout.weight(.medium))

                evidenceChip

                Text(boundary.holdsBecause)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                brokenLine
            }

            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 7)
                .fill(tint.opacity(0.08))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 7)
                .strokeBorder(tint.opacity(0.35), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
        .accessibilityIdentifier("boundary.\(boundary.id)")
    }

    private var icon: some View {
        Image(systemName: symbol)
            .font(.body)
            .foregroundStyle(tint)
            .frame(width: 18)
            .padding(.top, 1)
            .accessibilityHidden(true)
    }

    private var brokenLine: some View {
        HStack(spacing: 6) {
            Text("broken:")
                .font(.caption2)
                .foregroundStyle(.tertiary)
            Text(boundary.brokenMeans)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var evidenceChip: some View {
        switch boundary.evidence {
        case .test(let name):
            Text(name)
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background {
                    Capsule().fill(Color.secondary.opacity(0.12))
                }
                .help("Held by this test. The test is the authority; this view only names it.")
                .fixedSize()
        case .conformanceGap:
            Text("conformance gap")
                .font(.caption2)
                .foregroundStyle(.orange)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background {
                    Capsule().fill(Color.orange.opacity(0.14))
                }
                .help("No test holds this yet. Shown as debt, not as a pass.")
                .fixedSize()
        }
    }

    private var tint: Color {
        switch boundary.evidence {
        case .test: Color(red: 0.184, green: 0.490, blue: 0.310)
        case .conformanceGap: .orange
        }
    }

    private var symbol: String {
        switch boundary.evidence {
        case .test: "checkmark.shield"
        case .conformanceGap: "exclamationmark.shield"
        }
    }

    private var accessibilityText: String {
        let evidence: String
        switch boundary.evidence {
        case .test(let name): evidence = "held by \(name)"
        case .conformanceGap: evidence = "conformance gap"
        }
        return "\(boundary.invariant). \(boundary.holdsBecause). Broken means \(boundary.brokenMeans). \(evidence)."
    }
}

#Preview("Boundaries") {
    BoundariesView()
        .frame(width: 900, height: 620)
}
