//
//  BatchActionBar.swift
//  The Vault
//
//  Appears when multiple items are selected: batch tag, add-to-project,
//  copy paths, reveal, and clear selection.
//

import SwiftUI

struct BatchActionBar: View {
    @EnvironmentObject private var store: LibraryStore

    var body: some View {
        HStack(spacing: 12) {
            Text("\(store.selection.count) selected")
                .font(.callout.weight(.medium))
                .foregroundStyle(Theme.textPrimary)

            Divider().frame(height: 16).overlay(Theme.stroke)

            Menu {
                ForEach(store.tags) { tag in
                    Button {
                        store.applyTag(tag.id, to: store.selection)
                    } label: { Label(tag.name, systemImage: "tag") }
                }
            } label: {
                Label("Tag", systemImage: "tag")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            Menu {
                ForEach(store.projects) { project in
                    Button(project.name) {
                        store.addItems(store.selection, toProject: project.id)
                    }
                }
                if store.projects.isEmpty { Text("No projects yet") }
            } label: {
                Label("Add to Project", systemImage: "folder.badge.plus")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            Button {
                store.analyze(store.selection, force: false)
            } label: { Label("Analyze", systemImage: "wand.and.stars") }
            .buttonStyle(.plain)
            .disabled(store.isAnalyzing)

            Button {
                store.setReviewState(.approved, for: store.selection)
            } label: { Label("Approve", systemImage: "checkmark.circle") }
            .buttonStyle(.plain)

            Button {
                store.setReviewState(.discarded, for: store.selection)
            } label: { Label("Discard", systemImage: "trash.slash") }
            .buttonStyle(.plain)

            Button {
                NSPasteboard.general.writeFileURLs(store.selectedURLs)
            } label: { Label("Copy Paths", systemImage: "doc.on.clipboard") }
            .buttonStyle(.plain)

            Button {
                NSWorkspace.shared.reveal(store.selectedURLs)
            } label: { Label("Reveal", systemImage: "magnifyingglass") }
            .buttonStyle(.plain)

            Spacer()

            Button {
                store.clearSelection()
            } label: { Label("Clear", systemImage: "xmark") }
            .buttonStyle(.plain)
            .foregroundStyle(Theme.textSecondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Theme.surfaceRaised)
        .overlay(alignment: .bottom) { Divider().overlay(Theme.stroke) }
    }
}
