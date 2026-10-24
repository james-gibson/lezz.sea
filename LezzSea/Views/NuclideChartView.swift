//
//  NuclideChartView.swift
//  LezzSea
//
//  Two views of one data set: the compact threat × mechanism table (the
//  periodic-table view) and the isotope chart that resolves each threat class
//  into its variants and their decay channels.
//
//  Self-contained by design. No AppModel, no URLSession, no file access, no
//  private API — so this view drops into a WidgetKit extension unchanged.
//

import SwiftUI

struct NuclideChartView: View {

    enum Mode: String, CaseIterable, Identifiable {
        case nuclides
        case table

        var id: String { rawValue }
        var title: String { self == .nuclides ? "Isotopes" : "Table" }
    }

    @State private var mode: Mode = .nuclides
    @State private var selection: String? = NuclideChart.allIsotopes.first?.id

    private var selected: NuclideChart.Isotope? {
        NuclideChart.allIsotopes.first { $0.id == selection }
    }

    var body: some View {
        GeometryReader { proxy in
            VStack(spacing: 0) {
                header
                Divider()

                // The lattice needs height, the exposure block needs width.
                // Side by side when the pane can afford both; stacked with a
                // shorter detail block when it cannot.
                if proxy.size.width >= 760 {
                    HStack(spacing: 0) {
                        chartPane
                        Divider()
                        ScrollView { detail }
                            .frame(width: 360)
                    }
                } else {
                    chartPane
                    Divider()
                    ScrollView { detail }
                        .frame(maxHeight: 200)
                }

                Divider()
                legend
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Isotope chart of threat classes")
        .accessibilityIdentifier("isotopes.root")
    }

    // MARK: - Header

    private var header: some View {
        let counts = NuclideChart.counts
        return VStack(alignment: .leading, spacing: 6) {
            Text("Isotope chart")
                .font(.title3.weight(.semibold))

            Text("Each threat class resolved into its variants; each mechanism that acts on it is a decay channel. The exposure block answers *exposed to what*: source term, pathway, dose, effect.")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                Text("\(counts.isotopes) isotopes · \(counts.closed) closed · \(counts.open) with an open channel")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                Spacer(minLength: 8)

                Picker("Isotope view", selection: $mode) {
                    ForEach(Mode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 150)
                .help("Switch between the chart and the compact matrix")
                .accessibilityIdentifier("isotopes.mode")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Isotope chart

    private var chartPane: some View {
        GeometryReader { proxy in
            ScrollView([.horizontal, .vertical]) {
                Group {
                    switch mode {
                    case .nuclides: nuclideChart
                    case .table: matrixTable
                    }
                }
                .padding(16)
                // At least the viewport width, so a narrow lattice sits at
                // the leading edge instead of floating in the middle.
                .frame(minWidth: proxy.size.width, alignment: .leading)
            }
        }
    }

    private var nuclideChart: some View {
        Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 8) {
            GridRow {
                Text("threat class")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                ForEach(1...NuclideChart.maxMass, id: \.self) { mass in
                    Text("N = \(mass)")
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                        .frame(width: 104, alignment: .leading)
                }
            }

            ForEach(NuclideChart.elements) { element in
                GridRow(alignment: .top) {
                    elementLabel(element)
                    ForEach(1...NuclideChart.maxMass, id: \.self) { mass in
                        if let isotope = element.isotope(mass: mass) {
                            IsotopeCell(
                                isotope: isotope,
                                isSelected: selection == isotope.id
                            ) {
                                selection = isotope.id
                            }
                        } else {
                            RoundedRectangle(cornerRadius: 7)
                                .fill(Color.secondary.opacity(0.08))
                                .frame(width: 104, height: 66)
                                .overlay {
                                    Text("·")
                                        .font(.caption)
                                        .foregroundStyle(.tertiary)
                                }
                                .accessibilityHidden(true)
                        }
                    }
                }
            }
        }
    }

    private func elementLabel(_ element: NuclideChart.Element) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text(element.symbol)
                    .font(.body.monospaced().weight(.bold))
                Text("Z=\(element.z)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
            Text(element.name)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("\(element.isotopes.count) variant\(element.isotopes.count == 1 ? "" : "s")")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .frame(width: 132, alignment: .leading)
        .padding(.top, 6)
    }

    // MARK: - Table (the periodic-table view)

    private var matrixTable: some View {
        Grid(alignment: .leading, horizontalSpacing: 3, verticalSpacing: 3) {
            GridRow {
                Text("threat")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(width: 170, alignment: .leading)
                ForEach(NuclideChart.Mechanism.allCases) { mechanism in
                    Text(mechanism.code)
                        .font(.system(size: 9, weight: .bold).monospaced())
                        .foregroundStyle(.secondary)
                        .frame(width: 56)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }

            ForEach(NuclideChart.allIsotopes) { isotope in
                GridRow {
                    HStack(spacing: 5) {
                        Text(isotope.code)
                            .font(.caption2.monospaced())
                            .foregroundStyle(.tertiary)
                        Text(isotope.name)
                            .font(.caption2)
                            .lineLimit(1)
                    }
                    .frame(width: 170, alignment: .leading)

                    ForEach(NuclideChart.Mechanism.allCases) { mechanism in
                        TableCell(
                            channel: NuclideChart.channel(isotope, mechanism),
                            mechanism: mechanism
                        )
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Threat by mechanism matrix")
        .accessibilityIdentifier("isotopes.matrix")
    }

    // MARK: - Detail

    /// The exposure block plus the channel table.
    @ViewBuilder
    private var detail: some View {
        if let isotope = selected {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(isotope.code)
                        .font(.headline.monospaced())
                    Text(isotope.name)
                        .font(.callout)
                    Text(isotope.status.mark)
                        .foregroundStyle(Self.color(for: isotope.status))
                        .accessibilityLabel(isotope.status.word)
                    Spacer()
                    Text("\(isotope.channels.count) channel\(isotope.channels.count == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text("exposure")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tertiary)

                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 3) {
                    GridRow {
                        Text("source term").font(.caption2).foregroundStyle(.tertiary)
                        Text(isotope.exposure.source).font(.caption)
                    }
                    GridRow {
                        Text("pathway").font(.caption2).foregroundStyle(.tertiary)
                        Text(isotope.exposure.pathway).font(.caption)
                    }
                    GridRow {
                        Text("dose").font(.caption2).foregroundStyle(.tertiary)
                        Text(isotope.exposure.dose).font(.caption)
                    }
                    GridRow {
                        Text("effect").font(.caption2).foregroundStyle(.tertiary)
                        Text("\(isotope.exposure.effect.word) — \(isotope.exposure.effectNote)")
                            .font(.caption)
                    }
                }

                Text("decay channels")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tertiary)

                // One row per channel, two lines, rather than a five-column
                // grid: the detail pane is narrow when it sits beside the
                // chart, and a squeezed grid wraps words like "closed" mid-word.
                VStack(alignment: .leading, spacing: 7) {
                    ForEach(isotope.channels) { channel in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(alignment: .firstTextBaseline, spacing: 6) {
                                Text(channel.mechanism.name)
                                    .font(.caption)

                                Spacer(minLength: 6)

                                Text(channel.status.mark)
                                    .foregroundStyle(Self.color(for: channel.status))
                                    .accessibilityHidden(true)

                                Text(channel.status.word)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }

                            HStack(spacing: 4) {
                                Text(channel.label)
                                    .font(.caption2.monospaced())
                                    .foregroundStyle(.secondary)
                                Text("·")
                                    .foregroundStyle(.tertiary)
                                Text(channel.mechanism.daughter)
                                Text("·")
                                    .foregroundStyle(.tertiary)
                                Text(channel.mechanism.residence)
                                    .monospacedDigit()
                            }
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(
                            "\(channel.mechanism.name): \(channel.label), \(channel.status.word). Becomes \(channel.mechanism.daughter) after \(channel.mechanism.residence)."
                        )
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        } else {
            Text("Select a nuclide to see its decay channels.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
        }
    }

    // MARK: - Legend

    private var legend: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Two stacked rows rather than a horizontal `ViewThatFits`: the
            // candidate measurement gives this text an enormous ideal height
            // at narrow widths, which the parent scroll view then adopts.
            statusLegend
            openChannelKey

            Text("Schematic exposure model: the source term is work, the dose is accumulated 42i distance or filter occupancy. No ionizing radiation, no radiological quantity (Bq, Gy, Sv), no safety function. Source: smoke-alarm docs/design-matrices.md §2, §5, §7; ADR 0012.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
    }

    private var statusLegend: some View {
        HStack(spacing: 16) {
            ForEach(NuclideChart.Status.allCases) { status in
                HStack(spacing: 5) {
                    Circle()
                        .fill(Self.color(for: status))
                        .frame(width: 8, height: 8)
                    Text("\(status.mark) \(status.word)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(status.word) channels")
            }
        }
    }

    private var openChannelKey: some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 2)
                .strokeBorder(Self.color(for: .open), style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
                .frame(width: 12, height: 9)
            Text("a channel in this class is still open")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("A dashed cell has a channel that is still open")
    }

    // MARK: - Colours

    /// The status palette from `tools/design-matrices.py`, so the app and the
    /// generated SVG cannot drift apart.
    static func color(for status: NuclideChart.Status) -> Color {
        switch status {
        case .closed: Color(red: 0.184, green: 0.490, blue: 0.310)
        case .partial: Color(red: 0.722, green: 0.525, blue: 0.043)
        case .open: Color(red: 0.667, green: 0.200, blue: 0.200)
        }
    }
}

// MARK: - Cells

private struct IsotopeCell: View {
    let isotope: NuclideChart.Isotope
    let isSelected: Bool
    let action: () -> Void

    private var tint: Color { NuclideChartView.color(for: isotope.status) }

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    Text(isotope.code)
                        .font(.caption.monospaced().weight(.semibold))
                    Spacer(minLength: 0)
                    Text(isotope.status.mark)
                        .font(.caption2)
                        .foregroundStyle(tint)
                }

                Text(isotope.short)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Spacer(minLength: 0)

                HStack(spacing: 2) {
                    ForEach(isotope.channels) { channel in
                        Capsule()
                            .fill(NuclideChartView.color(for: channel.status))
                            .frame(width: 8, height: 3)
                    }
                }
            }
            .padding(7)
            .frame(width: 104, height: 66, alignment: .topLeading)
            .background {
                RoundedRectangle(cornerRadius: 7)
                    .fill(tint.opacity(0.14))
            }
            .overlay {
                if isotope.hasOpenChannel {
                    RoundedRectangle(cornerRadius: 7)
                        .strokeBorder(
                            NuclideChartView.color(for: .open),
                            style: StrokeStyle(lineWidth: 1, dash: [3, 2])
                        )
                } else if isSelected {
                    RoundedRectangle(cornerRadius: 7)
                        .strokeBorder(Color.accentColor, lineWidth: 2)
                } else {
                    RoundedRectangle(cornerRadius: 7)
                        .strokeBorder(tint.opacity(0.45), lineWidth: 1)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 7))
        }
        // A Button rather than `.onTapGesture`, so the cell is reachable from
        // the keyboard and activatable by VoiceOver.
        .buttonStyle(.plain)
        .help("\(isotope.name) — \(channelCount)")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(isotope.name), \(isotope.status.word), \(channelCount)")
        .accessibilityHint("Shows its exposure and decay channels")
        .accessibilityAddTraits(.isButton)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("isotope.\(isotope.id)")
    }

    private var channelCount: String {
        "\(isotope.channels.count) channel\(isotope.channels.count == 1 ? "" : "s")"
    }
}

private struct TableCell: View {
    let channel: NuclideChart.Channel?
    let mechanism: NuclideChart.Mechanism

    var body: some View {
        let tint = channel.map { NuclideChartView.color(for: $0.status) }
        VStack(spacing: 1) {
            Text(channel?.status.mark ?? "·")
                .font(.system(size: 10))
            Text(channel?.label ?? "")
                .font(.system(size: 9))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .foregroundStyle(channel == nil ? Color.secondary.opacity(0.55) : Color.primary)
        .frame(width: 56, height: 28)
        .background {
            RoundedRectangle(cornerRadius: 3)
                .fill(tint?.opacity(channel == nil ? 0 : 0.18) ?? Color.clear)
        }
        .help(channel.map { "\(mechanism.name): \($0.label)" } ?? "\(mechanism.name): not addressed")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            channel.map { "\(mechanism.name): \($0.label), \($0.status.word)" }
                ?? "\(mechanism.name): not addressed"
        )
    }
}

#Preview("Isotopes") {
    NuclideChartView()
        .frame(width: 1000, height: 780)
}
