//
//  SidebarView.swift
//  The Vault
//
//  Left navigation tree: Library shortcuts, Sources (with hot-plug / availability
//  state), Projects, and Tags. Selecting a row scopes the browser. Folders can
//  be dropped here to add new sources.
//

import SwiftUI
import UniformTypeIdentifiers

struct SidebarView: View {
    @EnvironmentObject private var store: LibraryStore
    @State private var showNewProject = false
    @State private var renamingSource: Source?
    @State private var renameText = ""

    var body: some View {
        List(selection: Binding(
            get: { store.sidebarSelection },
            set: { store.sidebarSelection = $0 ?? .allMedia })) {

            librarySection
            sourcesSection
            projectsSection
            tagsSection
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .background(Theme.surface)
        .safeAreaInset(edge: .bottom) { sidebarFooter }
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            handleFolderDrop(providers); return true
        }
        .sheet(isPresented: $showNewProject) { NewProjectSheet() }
        .sheet(item: $renamingSource) { source in
            RenameSourceSheet(source: source, text: $renameText) { newName in
                store.renameSource(source.id, to: newName)
            }
        }
    }

    // MARK: Sections

    private var librarySection: some View {
        Section("Library") {
            row(.allMedia, title: "All Media", symbol: "photo.stack",
                count: store.items.count)
            row(.untagged, title: "Untagged", symbol: "tag.slash",
                count: store.items.filter { $0.tagIDs.isEmpty }.count)
        }
    }

    private var sourcesSection: some View {
        Section("Sources") {
            if store.globalSources.isEmpty {
                Text("No sources yet")
                    .font(.caption)
                    .foregroundStyle(Theme.textTertiary)
            }
            // Only browser (non-project) sources appear here; project sources
            // live inside their project.
            ForEach(store.globalSources) { source in
                SourceRow(source: source)
                    .tag(SidebarSelection.source(source.id))
                    .contextMenu { sourceContextMenu(source) }
            }
        }
    }

    private var projectsSection: some View {
        Section {
            ForEach(store.projects) { project in
                Label {
                    HStack {
                        Text(project.name)
                        Spacer()
                        Text("\(project.itemCount)")
                            .font(.caption)
                            .foregroundStyle(Theme.textTertiary)
                    }
                } icon: {
                    Image(systemName: project.type.symbolName)
                        .foregroundStyle(Color(hex: project.type.accentHex) ?? Theme.accent)
                }
                .tag(SidebarSelection.project(project.id))
                .contextMenu { projectContextMenu(project) }
            }
        } header: {
            HStack {
                Text("Projects")
                Spacer()
                Button { showNewProject = true } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.textSecondary)
                .help("New project")
            }
        }
    }

    private var tagsSection: some View {
        Section("Tags") {
            ForEach(store.tags) { tag in
                Label {
                    Text(tag.name)
                } icon: {
                    Circle().fill(tag.color).frame(width: 10, height: 10)
                }
                .tag(SidebarSelection.tag(tag.id))
                .contextMenu {
                    Button("Delete Tag", role: .destructive) { store.deleteTag(tag.id) }
                }
            }
        }
    }

    private var sidebarFooter: some View {
        Button {
            SourcePicker.present(into: store)
        } label: {
            Label("Add Source", systemImage: "plus.rectangle.on.folder")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .tint(Theme.accent)
        .padding(10)
    }

    // MARK: Rows & menus

    private func row(_ selection: SidebarSelection, title: String,
                     symbol: String, count: Int) -> some View {
        Label {
            HStack {
                Text(title)
                Spacer()
                Text("\(count)").font(.caption).foregroundStyle(Theme.textTertiary)
            }
        } icon: {
            Image(systemName: symbol).foregroundStyle(Theme.accent)
        }
        .tag(selection)
    }

    private func sourceContextMenu(_ source: Source) -> some View {
        Group {
            Button("Rename…") { renameText = source.label; renamingSource = source }
            Button("Analyze Footage") { store.analyzeSource(source.id) }
                .disabled(store.isAnalyzing || !source.isAvailable)
            Divider()
            Button("Re-index") { store.reindexSource(source.id) }
                .disabled(!source.isAvailable)
            Button("Reveal in Finder") { NSWorkspace.shared.reveal([source.url]) }
            Divider()
            Button("Remove Source", role: .destructive) { store.removeSource(source.id) }
        }
    }

    private func projectContextMenu(_ project: Project) -> some View {
        Group {
            Button("Rename") { /* inline rename handled in detail; placeholder */ }
            Button("Delete Project", role: .destructive) { store.deleteProject(project.id) }
        }
    }

    private func handleFolderDrop(_ providers: [NSItemProvider]) {
        for provider in providers {
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                var isDir: ObjCBool = false
                guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir),
                      isDir.boolValue else { return }
                DispatchQueue.main.async { store.addSource(url: url) }
            }
        }
    }
}

/// One source row with availability dot + indexed count.
private struct SourceRow: View {
    let source: Source

    var body: some View {
        Label {
            HStack(spacing: 6) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(source.label)
                        .lineLimit(1)
                        .foregroundStyle(source.isAvailable ? Theme.textPrimary : Theme.textTertiary)
                    if !source.isAvailable {
                        Text("Disconnected")
                            .font(.caption2)
                            .foregroundStyle(Theme.offline)
                    }
                }
                Spacer()
                Text("\(source.indexedItemCount)")
                    .font(.caption)
                    .foregroundStyle(Theme.textTertiary)
            }
        } icon: {
            Image(systemName: source.mediaType.symbolName)
                .foregroundStyle(source.isAvailable ? Theme.accent : Theme.offline)
        }
        .opacity(source.isAvailable ? 1 : 0.55)
    }
}
