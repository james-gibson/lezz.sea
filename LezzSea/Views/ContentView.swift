//
//  ContentView.swift
//  LezzSea
//

import SwiftUI

struct ContentView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isTargeted = false

    /// The poll loop moves offline → connecting → offline every few seconds.
    /// Announce only the transition into each state, not every retry.
    @State private var announcedOnline = false
    @State private var announcedOffline = false

    var body: some View {
        @Bindable var model = model

        NavigationSplitView {
            ClusterSidebar()
                .navigationSplitViewColumnWidth(
                    min: LayoutMetrics.sidebarMinimumWidth,
                    ideal: 250,
                    max: LayoutMetrics.sidebarMaximumWidth
                )
        } detail: {
            DashboardView()
        }
        .navigationSplitViewStyle(.balanced)
        .navigationTitle(model.selectedCluster?.name ?? "lezz.sea")
        .navigationSubtitle(
            model.selectedCluster?.endpoint.absoluteString
                ?? "adhd lights and MCP traffic"
        )
        // The floor that stops the sidebar and the detail pane from sharing
        // pixels. Paired with `.windowResizability(.contentMinSize)` in
        // LezzSeaApp, AppKit refuses to shrink the window past it.
        .frame(
            minWidth: LayoutMetrics.minimumWindowWidth,
            minHeight: LayoutMetrics.minimumWindowHeight
        )
        .toolbar {
            // The panel switch lives in the toolbar, not in a `TabView` strip
            // floating over the content. A toolbar item cannot overlap the
            // summary bar or the table header, and macOS gives it the standard
            // overflow behaviour when the window is narrow.
            ToolbarItem(placement: .principal) {
                Picker("Panel", selection: $model.tab) {
                    ForEach(AppModel.Tab.allCases) { tab in
                        Label(tab.title, systemImage: tab.symbol)
                            // When the toolbar collapses to icon-only, the
                            // segment's default accessibility label becomes the
                            // SF Symbol name ("waveform.path.ecg"). Name the
                            // segment explicitly instead.
                            .accessibilityLabel(tab.title)
                            .tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 230)
                .help("Switch between panels (⌘1–⌘5)")
                .accessibilityValue(model.tab.title)
                .accessibilityIdentifier("toolbar.panel")
            }

            ToolbarItemGroup(placement: .primaryAction) {
                if model.isDiscovering {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel("Discovering clusters")
                }

                Button {
                    Task { await model.refresh() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .help("Refresh lights (⌘R)")
                .accessibilityIdentifier("toolbar.refresh")

                Button {
                    Task { await model.discover() }
                } label: {
                    Label(
                        "Discover Clusters",
                        systemImage: "antenna.radiowaves.left.and.right"
                    )
                }
                .help("Discover adhd clusters (⇧⌘R)")
                .accessibilityIdentifier("toolbar.discover")
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
        // The toast sits above the status bar (26pt) rather than under the
        // toolbar, where it used to cover the summary bar and the first table
        // row. Padding is the status bar plus a gap.
        .overlay(alignment: .bottom) {
            ToastView()
                .padding(.bottom, 40)
                .allowsHitTesting(false)
                .animation(
                    reduceMotion ? nil : .easeInOut(duration: 0.2),
                    value: model.toast
                )
        }
        .sheet(isPresented: $model.isAddingCluster) {
            AddClusterSheet()
                .environment(model)
        }
        .onChange(of: model.connection) { _, connection in
            announceIfNeeded(connection)
        }
        .accessibilityIdentifier("content.root")
    }

    private func announceIfNeeded(_ connection: AppModel.Connection) {
        switch connection {
        case .online:
            guard !announcedOnline else { return }
            announcedOnline = true
            announcedOffline = false
            let name = model.selectedCluster?.name ?? "the cluster"
            AccessibilityAnnouncer.announce("Connected to \(name)")

        case .offline(let message):
            guard !announcedOffline else { return }
            announcedOffline = true
            announcedOnline = false
            AccessibilityAnnouncer.announce("Cluster unreachable. \(message)", priority: .high)

        case .idle, .connecting:
            break
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
                    .accessibilityHidden(true)

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
        // A drop target is a passive surface; the drop itself is announced by
        // the toast. Keep it out of the VoiceOver element tree.
        .accessibilityHidden(true)
    }
}

// MARK: - Toast

private struct ToastView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
                .padding(.horizontal, 16)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .accessibilityLabel("Notice: \(toast)")
                .accessibilityAddTraits(.isStaticText)
                .task(id: toast) {
                    AccessibilityAnnouncer.announce(toast)
                    try? await Task.sleep(for: .seconds(3))
                    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) {
                        model.toast = nil
                    }
                }
        }
    }
}

// MARK: - Status bar

private struct StatusBar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: connectionSymbol)
                .foregroundStyle(connectionColor)
                .imageScale(.small)
                .accessibilityHidden(true)

            Text(model.connection.label)
                .lineLimit(1)

            if let lastRefresh = model.lastRefresh {
                Text("· \(lastRefresh, format: .relative(presentation: .named))")
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
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
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("status.connection")
    }

    /// Shape as well as colour, for Differentiate Without Colour.
    private var connectionSymbol: String {
        switch model.connection {
        case .idle: "circle"
        case .connecting: "arrow.triangle.2.circlepath"
        case .online: "checkmark.circle.fill"
        case .offline: "exclamationmark.triangle.fill"
        }
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
