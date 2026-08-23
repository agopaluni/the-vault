//
//  MediaContextMenu.swift
//  The Vault
//
//  Shared right-click menu for media cells (grid, timeline, project, map):
//  tagging, add-to-project, reveal, copy paths, and project removal.
//

import SwiftUI

struct MediaContextMenu: View {
    @EnvironmentObject private var store: LibraryStore
    let item: MediaItem

    /// Items the action applies to: the current selection if `item` is part of
    /// it, otherwise just `item`.
    private var targetIDs: Set<UUID> {
        store.selection.contains(item.id) ? store.selection : [item.id]
    }

    var body: some View {
        Button("Open Preview") { store.detailItemID = item.id }
        Divider()

        Menu("Add Tag") {
            ForEach(store.tags) { tag in
                Button {
                    store.applyTag(tag.id, to: targetIDs)
                } label: {
                    Label(tag.name, systemImage: "tag")
                }
            }
            if store.tags.isEmpty { Text("No tags yet") }
        }

        if !store.projects.isEmpty {
            Menu("Add to Project") {
                ForEach(store.projects) { project in
                    Button(project.name) {
                        store.addItems(targetIDs, toProject: project.id)
                    }
                }
            }
        }

        if case .project(let pid) = store.sidebarSelection {
            Button("Remove from Project", role: .destructive) {
                store.removeItems(targetIDs, fromProject: pid)
            }
        }

        Divider()
        Button("Reveal in Finder") {
            NSWorkspace.shared.reveal(targetIDs.compactMap { store.item($0)?.url })
        }
        Button("Copy File Paths") {
            NSPasteboard.general.writeFileURLs(targetIDs.compactMap { store.item($0)?.url })
        }
    }
}
