//
//  Presentation.swift
//  LezzSea
//
//  Names and measurements the views share. Keeping them here means the table,
//  the summary bar and the tests all agree on one description of a light, and
//  that the window has one declared floor instead of an accidental one.
//

import CoreGraphics

// MARK: - Light status

/// The visual and spoken name for a light's status.
///
/// Status is never carried by colour alone: each status has a symbol whose
/// *shape* differs, so the table still reads under colour blindness,
/// Differentiate Without Colour, Increase Contrast, and greyscale printing.
enum LightStatusStyle {
    struct Style: Equatable {
        let label: String
        let symbol: String
    }

    static func style(for status: String) -> Style {
        switch status.lowercased() {
        case "green":
            return Style(label: "Green", symbol: "checkmark.circle.fill")
        case "red":
            return Style(label: "Red", symbol: "xmark.octagon.fill")
        case "yellow":
            return Style(label: "Yellow", symbol: "exclamationmark.triangle.fill")
        case "dark":
            return Style(label: "Dark", symbol: "circle.dotted")
        default:
            let trimmed = status.trimmingCharacters(in: .whitespacesAndNewlines)
            return Style(
                label: trimmed.isEmpty ? "Unknown" : trimmed.capitalized,
                symbol: "questionmark.circle"
            )
        }
    }

    static func label(for status: String) -> String {
        style(for: status).label
    }

    static func symbol(for status: String) -> String {
        style(for: status).symbol
    }
}

// MARK: - Counts

/// Spoken and visible plurals for the summary bar and its VoiceOver label.
enum CountText {
    /// `1 light`, `6 lights`.
    static func lights(_ value: Int) -> String {
        "\(value) light\(value == 1 ? "" : "s")"
    }

    /// `3 green lights`, `1 red light`.
    static func count(_ value: Int, _ name: String) -> String {
        "\(value) \(name) light\(value == 1 ? "" : "s")"
    }
}

// MARK: - Layout

/// The window's declared floor.
///
/// The floor is the point below which the sidebar, the summary bar and the
/// lights table start competing for the same pixels. `ContentView` applies it
/// as a minimum frame and `LezzSeaApp` pairs that with
/// `.windowResizability(.contentMinSize)`, so AppKit enforces it for the user.
enum LayoutMetrics {
    static let sidebarMinimumWidth: CGFloat = 220
    /// A wide sidebar must not eat the lights table's columns.
    static let sidebarMaximumWidth: CGFloat = 320

    static let minimumWindowWidth: CGFloat = 760
    static let minimumWindowHeight: CGFloat = 500

    static let preferredWindowWidth: CGFloat = 1_120
    static let preferredWindowHeight: CGFloat = 720

    static var minimumWindowSize: CGSize {
        CGSize(width: minimumWindowWidth, height: minimumWindowHeight)
    }

    static var preferredWindowSize: CGSize {
        CGSize(width: preferredWindowWidth, height: preferredWindowHeight)
    }
}
