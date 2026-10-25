//
//  DashboardView.swift
//  LezzSea
//

import SwiftUI

struct DashboardView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 0) {
            // The cluster summary belongs to the cluster-scoped panels. The
            // isotope chart and the boundary list are static, so they get the
            // whole pane and never show a connection they do not use.
            if model.selectedCluster != nil, model.tab.needsCluster {
                LightSummaryBar()

                if case .offline(let message) = model.connection {
                    OfflineBanner(message: message)
                }
            }

            Group {
                if model.tab.needsCluster, model.selectedCluster == nil {
                    NoClusterView()
                } else {
                    // A plain switch, not a `TabView`. `TabView` + `.tabItem`
                    // draws its own tab strip on top of the content on macOS,
                    // which is what overlapped the summary bar and the table
                    // header in the shipped build. The panel is chosen from
                    // the toolbar instead (`ContentView`), so the detail pane
                    // owns its whole frame.
                    switch model.tab {
                    case .lights:
                        LightsView()
                    case .events:
                        EventStreamView()
                    case .isotopes:
                        VStack(spacing: 0) {
                            NuclideChartView()
                            Divider()
                            IsotopeTestsSection()
                        }
                    case .boundaries:
                        BoundariesView()
                    case .scenarios:
                        ScenariosView()
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityElement(children: .contain)
            .accessibilityLabel(model.tab.title)
            .accessibilityIdentifier("dashboard.panel")
        }
    }
}

// MARK: - Empty state

private struct NoClusterView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ContentUnavailableView {
            Label("No Cluster", systemImage: "antenna.radiowaves.left.and.right")
        } description: {
            Text("lezz.sea shows the lights of an available adhd cluster. Start one, let discovery find it, or add its MCP endpoint. The isotope chart and the boundary list need no cluster.")
        } actions: {
            HStack {
                Button("Discover") {
                    Task { await model.discover() }
                }
                .accessibilityIdentifier("empty.discover")

                Button("Add Cluster…") {
                    model.isAddingCluster = true
                }
                .accessibilityIdentifier("empty.addCluster")

                Menu("Static Views") {
                    Button("Isotopes") { model.tab = .isotopes }
                    Button("Boundaries") { model.tab = .boundaries }
                    Button("Scenarios") { model.tab = .scenarios }
                }
                .accessibilityIdentifier("empty.staticViews")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Summary

private struct LightSummaryBar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        // Two layouts, chosen by what actually fits. The full one carries the
        // instance name and trust rung; the compact one drops them rather than
        // letting the row push its own contents underneath each other.
        ViewThatFits(in: .horizontal) {
            full
            compact
        }
        .font(.callout)
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.bar)
        .overlay(alignment: .bottom) { Divider() }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("summary.bar")
    }

    private var full: some View {
        HStack(spacing: 14) {
            badges

            Divider().frame(height: 14)

            Text(CountText.lights(model.summary.total))
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Spacer(minLength: 8)

            if let status = model.status {
                if let instance = status.instance {
                    Label(instance, systemImage: "server.rack")
                        .lineLimit(1)
                        .help("adhd instance")
                }

                if let rung = status.trustRung {
                    Text("rung \(rung)")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .help("Trust rung on the 42i capability lattice")
                }
            }
        }
    }

    private var compact: some View {
        HStack(spacing: 12) {
            badges
            Text(CountText.lights(model.summary.total))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
    }

    private var badges: some View {
        HStack(spacing: 14) {
            CountBadge(status: "green", color: .green, label: "green", value: model.summary.green)
            CountBadge(status: "red", color: .red, label: "red", value: model.summary.red)
            CountBadge(status: "yellow", color: .yellow, label: "yellow", value: model.summary.yellow)
            CountBadge(status: "dark", color: .secondary, label: "dark", value: model.summary.dark)
        }
        .fixedSize(horizontal: true, vertical: false)
    }
}

private struct CountBadge: View {
    let status: String
    let color: Color
    let label: String
    let value: Int

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: LightStatusStyle.symbol(for: status))
                .foregroundStyle(color)
                .imageScale(.small)
                .accessibilityHidden(true)

            Text("\(value)")
                .monospacedDigit()
                .fontWeight(.medium)

            Text(label)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(CountText.count(value, label))
    }
}

// MARK: - Offline banner

private struct OfflineBanner: View {
    @Environment(AppModel.self) private var model
    let message: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "wifi.exclamationmark")
                .accessibilityHidden(true)

            Text(message)
                .lineLimit(2)

            Spacer(minLength: 8)

            Button("Retry") {
                Task { await model.refresh() }
            }
            .buttonStyle(.link)
            .accessibilityIdentifier("banner.retry")
        }
        .font(.callout)
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.yellow.opacity(0.14))
        .overlay(alignment: .bottom) { Divider() }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Offline. \(message)")
    }
}
