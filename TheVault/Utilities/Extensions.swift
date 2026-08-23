//
//  Extensions.swift
//  The Vault
//
//  Shared small helpers used across the UI.
//

import SwiftUI
import AppKit

extension Date {
    /// Day-granularity key used to group media in the timeline.
    var dayStart: Date {
        Calendar.current.startOfDay(for: self)
    }

    var mediumDateTime: String {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f.string(from: self)
    }

    var timeOnly: String {
        let f = DateFormatter()
        f.dateStyle = .none
        f.timeStyle = .short
        return f.string(from: self)
    }

    var dayHeader: String {
        let f = DateFormatter()
        f.dateFormat = "EEEE, MMMM d, yyyy"
        return f.string(from: self)
    }

    var shortDate: String {
        let f = DateFormatter()
        f.dateFormat = "MMM d, yyyy"
        return f.string(from: self)
    }
}

extension View {
    /// Apply a rounded card background using the theme surface color.
    func cardBackground(_ color: Color = Theme.surface,
                        cornerRadius: CGFloat = Theme.cornerRadius) -> some View {
        background(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(color)
        )
    }
}

extension NSPasteboard {
    /// Place file URLs and their plain-text paths on the pasteboard.
    func writeFileURLs(_ urls: [URL]) {
        clearContents()
        writeObjects(urls as [NSPasteboardWriting])
        let paths = urls.map(\.path).joined(separator: "\n")
        setString(paths, forType: .string)
    }
}

extension NSWorkspace {
    /// Reveal a set of files in Finder, selecting them.
    func reveal(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        activateFileViewerSelecting(urls)
    }
}
