//
//  ContentView.swift
//  LezzSea
//

import SwiftUI

struct ContentView: View {
    @Environment(AppModel.self) private var model
    @State private var isTargeted = false

    var body: some View {
        @Bindable var model = model

        NavigationSplitView {
            ClusterSidebar()
                .navigationSplitViewColumnWidth(min: 220, ideal: 250)
        } detail: {
            DashboardView()
        }
        .navigationSplitViewStyle(.balanced)
        .navigationTitle(model.selectedCluster?.name ?? "lezz.sea")
        .navigationSubtitle(model.selectedCluster?.endpoint.absoluteString ?? "adhd lights and MCP traffic")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                if model.isDiscovering {
                    ProgressView()
                        .controlSize(.small)
                }

                Button {
                    Task { await model.refresh() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .help("Refresh lights (⌘R)")

                Button {
                    Task { await model.discover() }
                } label: {
                    Label("Discover Clusters", systemImage: "antenna.radiowaves.left.and.right")
                }
                .help("Discover adhd clusters (⇧⌘R)")
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            StatusBar()
        }
        .dropDestination(for: URL.self) { urls, _ in
            model.acceptDrop(urls)
            return true
        } isTargeted: {
            isTargeted = $0
        }
        .overlay {
            if isTargeted {
                DropOverlay()
            }
        }
        .overlay(alignment: .top) {
            ToastView()
                .animation(.easeInOut(duration: 0.2), value: model.toast)
        }
        .sheet(isPresented: $model.isAddingCluster) {
            AddClusterSheet()
                .environment(model)
        }
    }
}

// MARK: - Drop target

private struct DropOverlay: View {
    var body: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)

            VStack(spacing: 10) {
                Image(systemName: "arrow.down.doc")
                    .font(.system(size: 38, weight: .light))
                    .foregroundStyle(.tint)
                Text("Drop a log or cluster config")
                    .font(.headline)
                Text("A .jsonl file streams as events. A .yaml or .json config adds its adhd endpoint.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(32)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(.tint, style: StrokeStyle(lineWidth: 2, dash: [8, 6]))
                .padding(12)
        }
        .allowsHitTesting(false)
        .transition(.opacity)
    }
}

// MARK: - Toast

private struct ToastView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if let toast = model.toast {
            Text(toast)
                .font(.callout)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(.regularMaterial, in: Capsule())
                .overlay {
                    Capsule().strokeBorder(.separator, lineWidth: 0.5)
                }
                .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
                .padding(.top, 10)
                .transition(.move(edge: .top).combined(with: .opacity))
                .task(id: toast) {
                    try? await Task.sleep(for: .seconds(3))
                    withAnimation { model.toast = nil }
                }
        }
    }
}

// MARK: - Status bar

private struct StatusBar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 7) {
            Circle()
                .fill(connectionColor)
                .frame(width: 7, height: 7)

            Text(model.connection.label)
                .lineLimit(1)

            if let lastRefresh = model.lastRefresh {
                Text("· \(lastRefresh, format: .relative(presentation: .named))")
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 12)

            if let cluster = model.selectedCluster {
                Text(cluster.endpoint.absoluteString)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .font(.caption)
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }

    private var connectionColor: Color {
        switch model.connection {
        case .idle: .secondary
        case .connecting: .orange
        case .online: .green
        case .offline: .red
        }
    }
}

#Preview {
    ContentView()
        .environment(AppModel())
}
