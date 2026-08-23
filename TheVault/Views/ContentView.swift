//
//  ContentView.swift
//  The Vault
//
//  Top-level three-pane layout: source/project sidebar (left), the media
//  browser (center, grid/timeline/map), and a sliding detail panel (right).
//  A toolbar sits on top and a status bar runs along the bottom.
//

import SwiftUI
import UniformTypeIdentifiers

/// Switches between the projects-first Home screen and the library browser.
struct RootView: View {
    @EnvironmentObject private var store: LibraryStore

    var body: some View {
        switch store.route {
        case .home: HomeView()
        case .browser: ContentView()
        }
    }
}

struct ContentView: View {
    @EnvironmentObject private var store: LibraryStore

    var body: some View {
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 220, ideal: 250, max: 320)
        } detail: {
            mainArea
        }
        .background(Theme.background)
        .toolbar { VaultToolbar() }
        .onReceive(NotificationCenter.default.publisher(for: .vaultOpenURLs)) { note in
            if let urls = note.object as? [URL] {
                for url in urls { store.addSource(url: url) }
            }
        }
        .alert("Source", isPresented: Binding(
            get: { store.sourceMessage != nil },
            set: { if !$0 { store.sourceMessage = nil } })) {
            Button("OK", role: .cancel) { store.sourceMessage = nil }
        } message: {
            Text(store.sourceMessage ?? "")
        }
    }

    private var mainArea: some View {
        ZStack(alignment: .bottom) {
            HStack(spacing: 0) {
                VStack(spacing: 0) {
                    FilterBar()
                    Divider().overlay(Theme.stroke)
                    browserContent
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    Divider().overlay(Theme.stroke)
                    StatusBar()
                }

                // Sliding detail panel.
                if store.detailItemID != nil {
                    Divider().overlay(Theme.stroke)
                    DetailPanel()
                        .frame(width: 360)
                        .transition(.move(edge: .trailing))
                }
            }
            .animation(.easeInOut(duration: 0.22), value: store.detailItemID)
        }
        .background(Theme.background)
    }

    @ViewBuilder
    private var browserContent: some View {
        // A project in grid mode gets the dedicated reorderable project view;
        // timeline/map still apply to the project's members via the filter scope.
        if case .project(let pid) = store.sidebarSelection, store.viewMode == .grid {
            ProjectView(projectID: pid)
        } else {
            switch store.viewMode {
            case .grid:     MediaGridView()
            case .timeline: TimelineView()
            case .map:      MapBrowserView()
            }
        }
    }
}
