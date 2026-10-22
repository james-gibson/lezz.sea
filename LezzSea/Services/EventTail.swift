//
//  EventTail.swift
//  LezzSea
//

import Foundation

/// Follows a growing JSONL file and hands back complete lines.
///
/// adhd writes one JSON object per line to its stdout log. The tail opens the
/// file at its current end (after a small backfill so the view is not empty on
/// launch), then polls its size. A log adhd has not created yet is retried
/// until it appears, so starting the app before the service is harmless.
@MainActor
final class EventTail {
    var onLines: (@MainActor ([String]) -> Void)?
    var onOpen: (@MainActor () -> Void)?
    var onMissing: (@MainActor () -> Void)?

    private var target: URL?
    private var handle: FileHandle?
    private var offset: UInt64 = 0
    private var buffer: [UInt8] = []
    private var task: Task<Void, Never>?

    private let backfillBytes: UInt64 = 64 * 1024

    func start(url: URL) {
        stop()
        target = url
        task = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                if self.handle == nil {
                    self.openOrWait()
                } else {
                    self.poll()
                }
                try? await Task.sleep(for: .milliseconds(self.handle == nil ? 1_500 : 400))
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
        try? handle?.close()
        handle = nil
        target = nil
        offset = 0
        buffer.removeAll()
    }

    private func openOrWait() {
        guard
            let target,
            FileManager.default.fileExists(atPath: target.path),
            let opened = try? FileHandle(forReadingFrom: target)
        else {
            onMissing?()
            return
        }

        handle = opened
        let size = (try? opened.seekToEnd()) ?? 0
        let start = size > backfillBytes ? size - backfillBytes : 0
        try? opened.seek(toOffset: start)

        if let data = try? opened.read(upToCount: Int(size - start)), !data.isEmpty {
            var chunk = [UInt8](data)
            // A backfill can begin mid-line; drop the partial first line.
            if start > 0, let newline = chunk.firstIndex(of: 0x0A) {
                chunk.removeFirst(newline + 1)
            }
            deliver(chunk)
        }

        offset = size
        onOpen?()
    }

    private func poll() {
        guard let handle else { return }
        let size = (try? handle.seekToEnd()) ?? 0

        if size < offset {
            // The file was truncated or rotated.
            offset = 0
            buffer.removeAll()
        }
        guard size > offset else { return }

        try? handle.seek(toOffset: offset)
        guard let data = try? handle.read(upToCount: Int(size - offset)), !data.isEmpty else {
            return
        }
        offset = size
        deliver([UInt8](data))
    }

    private func deliver(_ bytes: [UInt8]) {
        buffer.append(contentsOf: bytes)

        var lines: [String] = []
        var start = 0
        for index in buffer.indices where buffer[index] == 0x0A {
            if index > start, let line = String(bytes: buffer[start..<index], encoding: .utf8) {
                lines.append(line)
            }
            start = index + 1
        }
        if start > 0 {
            buffer.removeFirst(start)
        }
        if !lines.isEmpty {
            onLines?(lines)
        }
    }
}
