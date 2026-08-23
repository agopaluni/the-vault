//
//  StatusBar.swift
//  The Vault
//
//  Bottom status strip: file count, total size, active-filter summary, and a
//  live indexing progress indicator.
//

import SwiftUI

struct StatusBar: View {
    @EnvironmentObject private var store: LibraryStore

    var body: some View {
        let items = store.filteredItems
        HStack(spacing: 14) {
            Label("\(items.count) items", systemImage: "photo.stack")
            Label(ByteCountFormatter.string(fromByteCount: store.totalFilteredSize,
                                             countStyle: .file),
                  systemImage: "internaldrive")

            if store.filter.activeCriteriaCount > 0 {
                Label("\(store.filter.activeCriteriaCount) filters",
                      systemImage: "line.3.horizontal.decrease.circle")
                    .foregroundStyle(Theme.accent)
            }

            if !store.selection.isEmpty {
                Text("· \(store.selection.count) selected")
                    .foregroundStyle(Theme.textSecondary)
            }

            Spacer()

            if store.isIndexing {
                HStack(spacing: 8) {
                    ProgressView(value: store.indexingProgress)
                        .frame(width: 90)
                    Text(store.indexingStatusText)
                        .lineLimit(1)
                        .foregroundStyle(Theme.textSecondary)
                }
            } else if store.isAnalyzing {
                HStack(spacing: 8) {
                    Image(systemName: "wand.and.stars").foregroundStyle(Theme.accent)
                    ProgressView(value: store.analysisProgress)
                        .frame(width: 90)
                    Text(store.analysisStatusText)
                        .lineLimit(1)
                        .foregroundStyle(Theme.textSecondary)
                }
            } else if store.isEnhancing {
                HStack(spacing: 8) {
                    Image(systemName: "sparkles").foregroundStyle(Theme.accent)
                    ProgressView(value: store.enhancementProgress)
                        .frame(width: 90)
                    Text(store.enhancementStatusText)
                        .lineLimit(1)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
        }
        .font(.caption)
        .foregroundStyle(Theme.textTertiary)
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(Theme.surface)
    }
}
