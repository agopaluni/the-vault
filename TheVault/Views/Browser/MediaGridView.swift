//
//  MediaGridView.swift
//  The Vault
//
//  The primary browser: a responsive, lazily-loaded thumbnail grid. Uses
//  LazyVGrid inside a ScrollView so 10k+ item libraries stay responsive —
//  only visible cells generate thumbnails. Supports click / ⌘-click / ⇧-click
//  selection, double-click to preview, drag-out, and a batch action bar.
//

import SwiftUI

struct MediaGridView: View {
    @EnvironmentObject private var store: LibraryStore
    @State private var thumbnailSize: CGFloat = 150

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: thumbnailSize, maximum: thumbnailSize * 1.6), spacing: 8)]
    }

    var body: some View {
        let items = store.filteredItems
        VStack(spacing: 0) {
            if store.selection.count > 1 { BatchActionBar() }

            if items.isEmpty {
                EmptyBrowserState()
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 8) {
                        ForEach(items) { item in
                            cell(for: item, in: items)
                        }
                    }
                    .padding(12)
                    // Slack so the last row always clears the size slider /
                    // status bar and stays clickable.
                    .padding(.bottom, 56)
                }
            }
        }
        .background(Theme.background)
        .safeAreaInset(edge: .bottom) { sizeSlider }
        .onAppear { store.setVisibleItems(items.map(\.id)) }
        .onChange(of: items.map(\.id)) { ids in store.setVisibleItems(ids) }
    }

    private func cell(for item: MediaItem, in items: [MediaItem]) -> some View {
        MediaThumbnailView(item: item, isSelected: store.selection.contains(item.id))
            .mediaDragSource(itemID: item.id, orderedIDs: items.map(\.id), store: store)
            .contextMenu { MediaContextMenu(item: item) }
    }

    private var sizeSlider: some View {
        HStack {
            Spacer()
            Image(systemName: "photo").font(.caption2).foregroundStyle(Theme.textTertiary)
            Slider(value: $thumbnailSize, in: 90...260).frame(width: 120)
            Image(systemName: "photo").font(.body).foregroundStyle(Theme.textTertiary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Theme.surface.opacity(0.9))
    }
}

/// Shown when no media matches the current scope/filter.
struct EmptyBrowserState: View {
    @EnvironmentObject private var store: LibraryStore

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: store.sources.isEmpty ? "externaldrive.badge.plus" : "line.3.horizontal.decrease.circle")
                .font(.system(size: 46))
                .foregroundStyle(Theme.textTertiary)
            Text(store.sources.isEmpty ? "No sources yet" : "No media matches your filters")
                .font(.title3)
                .foregroundStyle(Theme.textSecondary)
            if store.sources.isEmpty {
                Button {
                    SourcePicker.present(into: store)
                } label: {
                    Label("Add a Source Folder", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
            } else if store.filter.activeCriteriaCount > 0 {
                Button("Clear Filters") { store.filter.reset() }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background)
    }
}
