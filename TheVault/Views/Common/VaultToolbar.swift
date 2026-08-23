//
//  VaultToolbar.swift
//  The Vault
//
//  The unified window toolbar: add-source button, grid/timeline/map view
//  toggle, sort control, and selection utilities (reveal / copy paths).
//

import SwiftUI

struct VaultToolbar: ToolbarContent {
    @EnvironmentObject private var store: LibraryStore

    var body: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            Button {
                store.route = .home
            } label: {
                Label("Home", systemImage: "house")
            }
            .help("Back to Home")
        }

        ToolbarItem(placement: .navigation) {
            Button {
                SourcePicker.present(into: store)
            } label: {
                Label("Add Source", systemImage: "plus.rectangle.on.folder")
            }
            .help("Add a source folder from any mounted volume")
        }

        ToolbarItem(placement: .principal) {
            Picker("View", selection: $store.viewMode) {
                ForEach(BrowserViewMode.allCases) { mode in
                    Image(systemName: mode.symbolName)
                        .help(mode.rawValue)
                        .tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 140)
        }

        ToolbarItemGroup(placement: .primaryAction) {
            analyzeMenu
            sortMenu

            Button {
                NSWorkspace.shared.reveal(store.selectedURLs)
            } label: {
                Label("Reveal in Finder", systemImage: "magnifyingglass")
            }
            .disabled(store.selection.isEmpty)
            .help("Reveal selected files in Finder")

            Button {
                NSPasteboard.general.writeFileURLs(store.selectedURLs)
            } label: {
                Label("Copy Paths", systemImage: "doc.on.clipboard")
            }
            .disabled(store.selection.isEmpty)
            .help("Copy file paths of selected media to the clipboard")
        }
    }

    private var analyzeMenu: some View {
        Menu {
            Button {
                store.analyze(store.selection, force: false)
            } label: { Label("Analyze Selected (\(store.selection.count))", systemImage: "wand.and.stars") }
                .disabled(store.selection.isEmpty)

            Button {
                store.analyze(Set(store.filteredItems.map(\.id)), force: false)
            } label: { Label("Analyze All Shown", systemImage: "sparkles.rectangle.stack") }

            Divider()
            Button {
                store.analyze(store.selection, force: true)
            } label: { Label("Re-analyze Selected", systemImage: "arrow.clockwise") }
                .disabled(store.selection.isEmpty)
        } label: {
            Label("Analyze", systemImage: "wand.and.stars")
        }
        .help("Run the on-device analysis pass over selected or shown footage")
        .disabled(store.isAnalyzing)
    }

    private var sortMenu: some View {
        Menu {
            ForEach(SortKey.allCases) { key in
                Button {
                    if store.filter.sortKey == key {
                        store.filter.sortDirection = store.filter.sortDirection.toggled
                    } else {
                        store.filter.sortKey = key
                    }
                } label: {
                    HStack {
                        Text(key.rawValue)
                        if store.filter.sortKey == key {
                            Image(systemName: store.filter.sortDirection.symbolName)
                        }
                    }
                }
            }
        } label: {
            Label("Sort: \(store.filter.sortKey.rawValue)", systemImage: "arrow.up.arrow.down")
        }
        .help("Sort order")
    }
}
