//
//  ClusterSidebar.swift
//  LezzSea
//

import AppKit
import SwiftUI

struct ClusterSidebar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        List(selection: selection) {
            Section("Clusters") {
                ForEach(model.clusters) { cluster in
                    ClusterRow(
                        cluster: cluster,
                        isConnected: cluster.id == model.selectedClusterID && model.connection.isOnline
                    )
                    .tag(cluster.id)
                    .contextMenu {
                        Button("Copy Endpoint") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(cluster.endpoint.absoluteString, forType: .string)
                        }
                        if cluster.source == .manual {
                            Divider()
                            Button("Remove", role: .destructive) {
                                model.removeCluster(cluster)
                            }
                        }
                    }
                }
            }

            if model.autoDiscover && model.isDiscovering {
                Section {
                    Label("Discovering clusters…", systemImage: "antenna.radiowaves.left.and.right")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .listStyle(.sidebar)
        .accessibilityLabel("Clusters")
        .accessibilityIdentifier("sidebar.clusters")
        .safeAreaInset(edge: .bottom, spacing: 0) {
            HStack {
                Button {
                    model.isAddingCluster = true
                } label: {
                    Label("Add Cluster", systemImage: "plus")
                }
                .buttonStyle(.borderless)
                .accessibilityIdentifier("sidebar.addCluster")

                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.bar)
            .overlay(alignment: .top) { Divider() }
        }
    }

    private var selection: Binding<String?> {
        Binding(get: { model.selectedClusterID }, set: { model.select($0) })
    }
}

private struct ClusterRow: View {
    let cluster: Cluster
    let isConnected: Bool

    var body: some View {
        HStack(spacing: 9) {
            // Shape and colour: a tick when connected, a dotted ring when not.
            Image(systemName: isConnected ? "checkmark.circle.fill" : "circle.dotted")
                .font(.caption)
                .foregroundStyle(isConnected ? Color.green : Color.secondary.opacity(0.7))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 1) {
                Text(cluster.name)
                    .lineLimit(1)

                Text(hostLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            if cluster.source == .registry {
                Image(systemName: "shippingbox")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .help("Published by the lezz cluster registry")
                    .accessibilityHidden(true)
            } else if cluster.source == .bonjour {
                Image(systemName: "bonjour")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .help("Advertised over Bonjour")
                    .accessibilityHidden(true)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spokenLabel)
        .accessibilityIdentifier("sidebar.row.\(cluster.id)")
    }

    private var hostLabel: String {
        if let host = cluster.endpoint.host, let port = cluster.endpoint.port {
            return "\(host):\(port)"
        }
        return cluster.endpoint.host ?? cluster.endpoint.absoluteString
    }

    /// The whole row as one spoken sentence: name, address, state, provenance.
    private var spokenLabel: String {
        var parts = [cluster.name, hostLabel, isConnected ? "Connected" : "Not connected"]

        switch cluster.source {
        case .manual: parts.append("Added by you")
        case .registry: parts.append("From the lezz cluster registry")
        case .bonjour: parts.append("Announced with Bonjour")
        case .local: parts.append("Local adhd instance")
        }

        return parts.joined(separator: ", ")
    }
}
