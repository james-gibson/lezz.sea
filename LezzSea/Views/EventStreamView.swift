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
        HStack(spacing: 10) {
            Picker("Filter", selection: $filter) {
                ForEach(Filter.allCases) { filter in
                    Text(filter.rawValue).tag(filter)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 300)

            Spacer()

            if model.eventsPaused {
                Text("\(model.backlog.count) held")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Toggle(isOn: pauseBinding) {
                Label(model.eventsPaused ? "Paused" : "Live", systemImage: model.eventsPaused ? "pause.fill" : "waveform")
            }
            .toggleStyle(.button)
            .help("Pause the live stream (⇧⌘P)")

            Toggle(isOn: $follow) {
                Label("Follow", systemImage: "arrow.down.to.line")
            }
            .toggleStyle(.button)
            .help("Scroll to the newest event")

            Button {
                model.clearEvents()
            } label: {
                Label("Clear", systemImage: "trash")
            }
            .help("Clear the event list (⌘K)")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
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
                Text("adhd logs every MCP request and response as JSON lines. Choose its log to stream it, or drop a .jsonl file on the window.")
            } actions: {
                HStack {
                    Button("Choose Log…") { model.chooseLog() }
                    Button("Use Default Log") { model.openDefaultLog() }
                }
            }
        } else if model.events.isEmpty {
            VStack(spacing: 10) {
                ProgressView()
                Text("Waiting for traffic")
                    .font(.headline)
                Text(shortPath)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .truncationMode(.middle)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
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
            .onAppear {
                guard follow, let last = filtered.last else { return }
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(60))
                    proxy.scrollTo(last.id, anchor: .bottom)
                }
            }
            .onChange(of: filtered.count) { _, _ in
                guard follow, !model.eventsPaused, let last = filtered.last else { return }
                withAnimation(.easeOut(duration: 0.12)) {
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

// MARK: - Row

private struct EventRow: View {
    let event: TrafficEvent

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 9) {
            Text(event.time ?? .distantPast, format: .dateTime.hour().minute().second())
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(event.time == nil ? .tertiary : .secondary)
                .frame(width: 64, alignment: .leading)

            Image(systemName: event.kind.symbol)
                .foregroundStyle(event.kind.tint)
                .frame(width: 14)

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
                    .foregroundStyle(.tertiary)
            }
        }
        .help(event.raw)
        .contextMenu {
            Button("Copy JSON Line") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(event.raw, forType: .string)
            }
        }
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
