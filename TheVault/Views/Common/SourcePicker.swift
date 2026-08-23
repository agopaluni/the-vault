//
//  SourcePicker.swift
//  The Vault
//
//  Presents a folder picker for adding source folders, and a small label
//  prompt so the user can name the origin (e.g. "A7IV - SD Card").
//

import AppKit

@MainActor
enum SourcePicker {
    /// Show an open panel allowing one or more folders, then add them as sources.
    static func present(into store: LibraryStore) {
        let panel = NSOpenPanel()
        panel.title = "Add Source Folder"
        panel.prompt = "Add Source"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.message = "Choose folders on any mounted volume — SD card, SSD, internal or external drive."

        panel.begin { response in
            guard response == .OK else { return }
            for url in panel.urls {
                let suggested = suggestedLabel(for: url)
                store.addSource(url: url, label: suggested)
            }
        }
    }

    private static func suggestedLabel(for url: URL) -> String {
        let folder = url.lastPathComponent
        let type = Source.guessMediaType(for: url)
        return "\(folder) - \(type.defaultLabel)"
    }
}
