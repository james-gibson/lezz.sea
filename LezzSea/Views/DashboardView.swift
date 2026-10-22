//
//  DashboardView.swift
//  LezzSea
//

import SwiftUI

struct DashboardView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model

        Group {
            if model.selectedCluster != nil {
                VStack(spacing: 0) {
                    LightSummaryBar()

                    if case .offline(let message) = model.connection {
                        OfflineBanner(message: message)
                    }

                    TabView(selection: $model.tab) {
                        LightsView()
                            .tabItem {
                                Label(AppModel.Tab.lights.title, systemImage: AppModel.Tab.lights.symbol)
                            }
                            .tag(AppModel.Tab.lights)

                        EventStreamView()
                            .tabItem {
                                Label(AppModel.Tab.events.title, systemImage: AppModel.Tab.events.symbol)
                            }
                            .tag(AppModel.Tab.events)
                    }
                    .padding(.top, 2)
                }
            } else {
                ContentUnavailableView {
                    Label("No Cluster", systemImage: "antenna.radiowaves.left.and.right")
                } description: {
                    Text("lezz.sea shows the lights of an available adhd cluster. Start one, let discovery find it, or add its MCP endpoint.")
                } actions: {
                    HStack {
                        Button("Discover") {
                            Task { await model.discover() }
                        }
                        Button("Add Cluster…") {
                            model.isAddingCluster = true
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Summary

private struct LightSummaryBar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 14) {
            CountBadge(color: .green, label: "green", value: model.summary.green)
            CountBadge(color: .red, label: "red", value: model.summary.red)
            CountBadge(color: .yellow, label: "yellow", value: model.summary.yellow)
            CountBadge(color: .secondary, label: "dark", value: model.summary.dark)

            Divider().frame(height: 14)

            Text("\(model.summary.total) light\(model.summary.total == 1 ? "" : "s")")
                .foregroundStyle(.secondary)

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
                        .help("Trust rung on the 42i capability lattice")
                }
            }
        }
        .font(.callout)
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .background(.bar)
        .overlay(alignment: .bottom) { Divider() }
    }
}

private struct CountBadge: View {
    let color: Color
    let label: String
    let value: Int

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(color)
                .frame(width: 9, height: 9)
            Text("\(value)")
                .monospacedDigit()
                .fontWeight(.medium)
            Text(label)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(value) \(label) lights")
    }
}

// MARK: - Offline banner

private struct OfflineBanner: View {
    @Environment(AppModel.self) private var model
    let message: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "wifi.exclamationmark")
            Text(message)
                .lineLimit(1)
            Spacer()
            Button("Retry") {
                Task { await model.refresh() }
            }
            .buttonStyle(.link)
        }
        .font(.callout)
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(.yellow.opacity(0.14))
        .overlay(alignment: .bottom) { Divider() }
    }
}
