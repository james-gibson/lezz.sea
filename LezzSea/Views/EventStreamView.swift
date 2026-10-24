//
//  EventStreamView.swift
//  LezzSea
//

import AppKit
import SwiftUI

struct EventStreamView: View {
    private enum Filter: String, CaseIterable, Identifiable {
        case all = "All"
        case requests = "Requests"
        case responses = "Responses"
        case lights = "Lights"

        var id: String { rawValue }

        func includes(_ event: TrafficEvent) -> Bool {
            switch self {
            case .all: true
            case .requests: event.kind == .request
            case .responses: event.kind == .response || event.kind == .error
            case .lights: event.kind == .lightUpdate
            }
        }
    }

    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var filter: Filter = .all
    @State private var query = ""
    @State private var follow = true

    var body: some View {
        VStack(spacing: 0) {
            controls
            Divider()
            content
        }
        .searchable(text: $query, placement: .toolbar, prompt: "Filter events")
    }

    // MARK: - Controls

    private var controls: some View {
        // Two arrangements of the same row. The full one keeps every label;
        // the compact one falls back to icon-only controls, so the row shrinks
        // by giving up text rather than by letting controls overlap.
        ViewThatFits(in: .horizontal) {
            controlRow(compact: false)
            controlRow(compact: true)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .controlSize(.regular)
        .frame(maxWidth: .infinity)
        .background(.bar)
        .accessibilityIdentifier("events.controls")
    }

    private func controlRow(compact: Bool) -> some View {
        HStack(spacing: 10) {
            Picker("Filter", selection: $filter) {
                ForEach(Filter.allCases) { filter in
                    Text(filter.rawValue).tag(filter)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(minWidth: compact ? 160 : 220, maxWidth: compact ? 220 : 300)
            .accessibilityLabel("Filter events")
            .accessibilityIdentifier("events.filter")

            Spacer(minLength: 8)

            if model.eventsPaused {
                Text("\(model.backlog.count) held")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .accessibilityLabel("\(model.backlog.count) events held while paused")
            }

            Toggle(isOn: pauseBinding) {
                Label(
                    model.eventsPaused ? "Paused" : "Live",
                    systemImage: model.eventsPaused ? "pause.fill" : "waveform"
                )
            }
            .toggleStyle(.button)
            .compactLabel(compact)
            .help("Pause the live stream (⇧⌘P)")
            .accessibilityLabel(model.eventsPaused ? "Resume the live stream" : "Pause the live stream")
            .accessibilityIdentifier("events.pause")

            Toggle(isOn: $follow) {
                Label("Follow", systemImage: "arrow.down.to.line")
            }
            .toggleStyle(.button)
            .compactLabel(compact)
            .help("Scroll to the newest event")
            .accessibilityLabel("Follow the newest event")
            .accessibilityIdentifier("events.follow")

            Button {
                model.clearEvents()
            } label: {
                Label("Clear", systemImage: "trash")
                    .compactLabel(compact)
            }
            .help("Clear the event list (⌘K)")
            .accessibilityLabel("Clear events")
            .accessibilityIdentifier("events.clear")
        }
    }

    private var pauseBinding: Binding<Bool> {
        Binding(get: { model.eventsPaused }, set: { _ in model.togglePause() })
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if model.logState == .missing {
            ContentUnavailableView {
                Label("No Traffic Log", systemImage: "doc.text.magnifyingglass")
            } description: {
                Text("adhd logs every MCP request and response as JSON lines. Choose its log to let lezz.sea read it, or drop a .jsonl file on the window.")
            } actions: {
                HStack {
                    Button("Choose Log…") { model.chooseLog() }
                        .accessibilityIdentifier("events.chooseLog")

                    Button("Use Default Log") { model.openDefaultLog() }
                        .accessibilityIdentifier("events.useDefaultLog")
                }
            }
        } else if model.events.isEmpty {
            VStack(spacing: 10) {
                ProgressView()
                    .accessibilityLabel("Waiting for traffic")

                Text("Waiting for traffic")
                    .font(.headline)

                Text(shortPath)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .truncationMode(.middle)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityElement(children: .combine)
        } else if filtered.isEmpty {
            ContentUnavailableView.search(text: query)
        } else {
            eventList
        }
    }

    private var eventList: some View {
        ScrollViewReader { proxy in
            List(filtered) { event in
                EventRow(event: event)
                    .id(event.id)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 3, leading: 10, bottom: 3, trailing: 10))
            }
            .listStyle(.inset)
            .accessibilityLabel("Events")
            .accessibilityIdentifier("events.list")
            .onAppear {
                guard follow, let last = filtered.last else { return }
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(60))
                    proxy.scrollTo(last.id, anchor: .bottom)
                }
            }
            .onChange(of: filtered.count) { _, _ in
                guard follow, !model.eventsPaused, let last = filtered.last else { return }
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.12)) {
                    proxy.scrollTo(last.id, anchor: .bottom)
                }
            }
        }
    }

    private var filtered: [TrafficEvent] {
        model.events.filter { event in
            guard filter.includes(event) else { return false }
            guard !query.isEmpty else { return true }
            return event.raw.localizedCaseInsensitiveContains(query)
                || event.summary.localizedCaseInsensitiveContains(query)
        }
    }

    private var shortPath: String {
        URL(fileURLWithPath: model.logPath).lastPathComponent
    }
}

// MARK: - Compact label

/// Falls back to an icon-only label when the controls row is tight. The icon
/// keeps its `.help` tooltip and its explicit accessibility label, so the
/// meaning survives the narrower rendering.
private struct CompactLabel: ViewModifier {
    let compact: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if compact {
            content.labelStyle(.iconOnly)
        } else {
            content.labelStyle(.titleAndIcon)
        }
    }
}

private extension View {
    func compactLabel(_ compact: Bool) -> some View {
        modifier(CompactLabel(compact: compact))
    }
}

// MARK: - Row

private struct EventRow: View {
    let event: TrafficEvent

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 9) {
            Text(timeText)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(event.time == nil ? .tertiary : .secondary)
                .frame(width: 68, alignment: .leading)
                .lineLimit(1)

            Image(systemName: event.kind.symbol)
                .foregroundStyle(event.kind.tint)
                .frame(width: 14)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 1) {
                Text(event.summary)
                    .font(.system(.callout, design: event.kind == .request ? .monospaced : .default))
                    .lineLimit(1)
                    .truncationMode(.middle)

                if let detail = event.detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .truncationMode(.middle)
                }
            }

            Spacer(minLength: 0)

            if let latency = event.latency {
                Text("\(latency, specifier: "%.0f") ms")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .help(event.raw)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spokenSummary)
        .accessibilityAction(named: Text("Copy JSON Line")) {
            copyJSON()
        }
        .contextMenu {
            Button("Copy JSON Line") {
                copyJSON()
            }
        }
    }

    private var timeText: String {
        guard let time = event.time else { return "—" }
        return time.formatted(date: .omitted, time: .standard)
    }

    /// One sentence per row, in the order a listener needs it: when, what
    /// kind, what it was, what changed, how long it took.
    private var spokenSummary: String {
        var parts: [String] = [timeText, event.kind.label, event.summary]
        if let detail = event.detail {
            parts.append(detail)
        }
        if let latency = event.latency {
            parts.append("\(Int(latency.rounded())) milliseconds")
        }
        return parts.joined(separator: ", ")
    }

    private func copyJSON() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(event.raw, forType: .string)
    }
}

extension TrafficEvent.Kind {
    var tint: Color {
        switch self {
        case .request: .blue
        case .response: .green
        case .lightUpdate: .yellow
        case .error: .red
        case .other: .secondary
        }
    }
}
