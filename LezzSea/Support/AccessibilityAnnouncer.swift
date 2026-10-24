//
//  AccessibilityAnnouncer.swift
//  LezzSea
//
//  VoiceOver announcements for state that changes without a focus change:
//  a toast, the connection coming up, the connection dropping. A visual-only
//  toast is silent to a screen-reader user, which is why this exists at all.
//

import AppKit

enum AccessibilityAnnouncer {
    /// Posts a spoken announcement through the focused window.
    ///
    /// Posting is inert when VoiceOver is off, so callers never need to check.
    static func announce(_ message: String, priority: NSAccessibilityPriorityLevel = .medium) {
        guard !message.isEmpty else { return }
        guard let element = NSApp.keyWindow ?? NSApp.mainWindow else { return }

        NSAccessibility.post(
            element: element,
            notification: .announcementRequested,
            userInfo: [
                .announcement: message,
                .priority: priority.rawValue,
            ]
        )
    }
}
