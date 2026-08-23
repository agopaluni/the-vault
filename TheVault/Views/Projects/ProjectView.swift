//
//  ProjectView.swift
//  The Vault
//
//  A single project, with three modes:
//   • All      — ordered members, drag to reorder, drag out to other apps.
//   • Flagged  — AI-flagged mistake/low-quality clips with reason chips and
//                bulk Approve / Discard (non-destructive — never deletes files).
//   • Content  — members grouped by content tag (talking head, B-roll, …).
//

import SwiftUI
import AppKit

struct ProjectView: View {
    @EnvironmentObject private var store: LibraryStore
    @EnvironmentObject private var settings: AppSettings
    let projectID: UUID

    enum Mode: String, CaseIterable, Identifiable {
        case all = "In Project"
        case sourceMedia = "Source Media"
        case flagged = "Flagged"
        case content = "By Content"
        var id: String { rawValue }
    }
    @State private var mode: Mode = .all
    @State private var renamingSource: Source?
    @State private var renameText = ""
    @State private var confirmClearProject = false

    private var project: Project? { store.project(projectID) }
    private var items: [MediaItem] { store.items(inProject: projectID) }
    private var projectSources: [Source] { store.sources(ownedBy: projectID) }
    private var flaggedItems: [MediaItem] {
        items.filter { !$0.qualityFlags.isEmpty }
            .sorted { a, b in
                let am = a.qualityFlags.contains { $0.isMistake }
                let bm = b.qualityFlags.contains { $0.isMistake }
                if am != bm { return am }               // mistakes first
                return a.qualityFlags.count > b.qualityFlags.count
            }
    }

    var body: some View {
        VStack(spacing: 0) {
            projectHeader
            Divider().overlay(Theme.stroke)
            content
        }
        .background(Theme.background)
        .onAppear { store.setVisibleItems(items.map(\.id)) }
        .onChange(of: items.map(\.id)) { ids in
            if mode != .sourceMedia { store.setVisibleItems(ids) }
        }
        .onChange(of: mode) { newMode in
            if newMode != .sourceMedia { store.setVisibleItems(items.map(\.id)) }
        }
        .sheet(item: $renamingSource) { source in
            RenameSourceSheet(source: source, text: $renameText) { newName in
                store.renameSource(source.id, to: newName)
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch mode {
        case .sourceMedia:
            SourceMediaView(projectID: projectID)
        case .all:
            if items.isEmpty { emptyState } else { orderedList }
        case .flagged:
            if items.isEmpty { emptyState } else {
                FlaggedTriageView(projectID: projectID, items: flaggedItems)
            }
        case .content:
            if items.isEmpty { emptyState } else { ContentGroupView(items: items) }
        }
    }

    // MARK: Header

    private var projectHeader: some View {
        VStack(spacing: 8) {
            HStack {
                if let project {
                    Image(systemName: project.type.symbolName)
                        .foregroundStyle(Color(hex: project.type.accentHex) ?? Theme.accent)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(project.name).font(.headline).foregroundStyle(Theme.textPrimary)
                        Text("\(project.type.displayName) · \(items.count) in project · "
                             + "\(store.poolItemsNotInProject(projectID).count) available · "
                             + "\(flaggedItems.count) flagged")
                            .font(.caption).foregroundStyle(Theme.textTertiary)
                    }
                }
                Spacer()
                if store.selection.isEmpty {
                    let toAnalyze = store.analyzableCount(Set(items.map(\.id)), force: false)
                    Button {
                        store.analyze(Set(items.map(\.id)), force: false)
                    } label: {
                        Label(toAnalyze > 0 ? "Analyze (\(toAnalyze))" : "Analyzed",
                              systemImage: "wand.and.stars")
                    }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(store.isAnalyzing || toAnalyze == 0)
                    enhanceButton
                    projectMenu
                }
            }
            if let error = store.enhancementError {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(Color.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            sourcesBar
            Picker("Mode", selection: $mode) {
                ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Theme.surface)
    }

    /// This project's own sources (separate from the browser's global sources),
    /// with add / rename / analyze / remove.
    private var sourcesBar: some View {
        FlowLayout(spacing: 6) {
            ForEach(projectSources) { source in
                HStack(spacing: 4) {
                    Circle().fill(source.isAvailable ? Theme.online : Theme.offline)
                        .frame(width: 6, height: 6)
                    Image(systemName: source.mediaType.symbolName).font(.system(size: 9))
                    Text(source.label).font(.caption)
                    Text("\(source.indexedItemCount)").font(.caption2).foregroundStyle(Theme.textTertiary)
                }
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(Capsule().fill(Theme.surfaceRaised))
                .foregroundStyle(source.isAvailable ? Theme.textPrimary : Theme.textTertiary)
                .contextMenu {
                    Button("Analyze Footage") { store.analyzeSource(source.id) }
                        .disabled(store.isAnalyzing || !source.isAvailable)
                    Button("Rename…") { renameText = source.label; renamingSource = source }
                    Button("Reveal in Finder") { NSWorkspace.shared.reveal([source.url]) }
                    Divider()
                    Button("Remove Source", role: .destructive) { store.removeSource(source.id) }
                }
            }

            Button { addProjectSource() } label: {
                Label("Add Source", systemImage: "plus")
                    .font(.caption)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Capsule().strokeBorder(Theme.stroke))
            }
            .buttonStyle(.plain)
            .foregroundStyle(Theme.accent)
        }
    }

    private func addProjectSource() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.prompt = "Add"
        guard panel.runModal() == .OK else { return }
        for url in panel.urls { store.addProjectSource(projectID, url: url) }
    }

    /// Bulk membership actions — curate from scratch, or pull the whole pool in.
    private var projectMenu: some View {
        Menu {
            Button {
                store.addItems(Set(store.poolItems(forProject: projectID).map(\.id)),
                               toProject: projectID)
            } label: { Label("Add All Source Media", systemImage: "plus.square.on.square") }

            Button(role: .destructive) { confirmClearProject = true } label: {
                Label("Clear Project Selection…", systemImage: "arrow.counterclockwise")
            }
            .disabled(items.isEmpty)
        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .confirmationDialog("Remove all \(items.count) clips from this project?",
                            isPresented: $confirmClearProject, titleVisibility: .visible) {
            Button("Remove All", role: .destructive) {
                store.clearProjectMembers(projectID)
                store.clearSelection()
                mode = .sourceMedia
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Your sources, footage, and files stay exactly as they are — this only clears which clips are selected into the project, so you can pick them yourself.")
        }
    }

    /// Claude enrichment. Disabled without a key (points the user to Settings)
    /// and labeled with how many clips would actually be sent (spends credits).
    @ViewBuilder
    private var enhanceButton: some View {
        let candidates = store.enrichmentCandidates(Set(items.map(\.id))).count
        Button {
            store.enhanceItems(Set(items.map(\.id)), apiKey: settings.claudeKey() ?? "")
        } label: {
            Label(store.isEnhancing ? "Enhancing…" : "Enhance with AI (\(candidates))",
                  systemImage: "sparkles")
        }
        .buttonStyle(.borderedProminent)
        .tint(Theme.accent)
        .controlSize(.small)
        .disabled(!settings.hasClaudeKey || store.isEnhancing || candidates == 0)
        .help(settings.hasClaudeKey
              ? "Send \(candidates) clip(s) to Claude for content tagging"
              : "Add a Claude API key in Settings ▸ Claude API")
    }

    private var emptyState: some View {
        let available = store.poolItems(forProject: projectID).count
        return VStack(spacing: 12) {
            Image(systemName: "tray").font(.system(size: 40)).foregroundStyle(Theme.textTertiary)
            Text("No footage added yet").foregroundStyle(Theme.textSecondary)
            if available > 0 {
                Text("\(available) clips are available from this project's sources. Pick the ones you want to include.")
                    .font(.caption).foregroundStyle(Theme.textTertiary)
                    .multilineTextAlignment(.center).frame(maxWidth: 340)
                Button { mode = .sourceMedia } label: {
                    Label("Browse Source Media", systemImage: "square.grid.2x2")
                }
                .buttonStyle(.borderedProminent).tint(Theme.accent)
            } else {
                Text("Add a source above to bring in footage, then choose what to include.")
                    .font(.caption).foregroundStyle(Theme.textTertiary)
                    .multilineTextAlignment(.center).frame(maxWidth: 340)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background)
    }

    // MARK: All (ordered, reorderable)

    private var orderedList: some View {
        List {
            ForEach(items) { item in
                ProjectRow(item: item)
                    .listRowBackground(Theme.background)
                    .onDrag {
                        if !store.selection.contains(item.id) { store.selection = [item.id] }
                        return MediaDrag.itemProvider(for: item)
                    }
                    .contextMenu { MediaContextMenu(item: item) }
            }
            .onMove(perform: move)
            .onDelete(perform: delete)
        }
        .listStyle(.inset)
        .scrollContentBackground(.hidden)
        .background(Theme.background)
    }

    private func move(from: IndexSet, to: Int) {
        var ids = items.map(\.id)
        ids.move(fromOffsets: from, toOffset: to)
        store.reorderProject(projectID, to: ids)
    }

    private func delete(_ offsets: IndexSet) {
        let ids = Set(offsets.map { items[$0].id })
        store.removeItems(ids, fromProject: projectID)
    }
}

// MARK: - Source media (the pool you curate from)

/// All media from the project's sources, with an "Add to Project" action.
/// Clips already in the project are marked so you can see what's left.
private struct SourceMediaView: View {
    @EnvironmentObject private var store: LibraryStore
    let projectID: UUID

    enum Scope: String, CaseIterable, Identifiable {
        case all = "All"
        case notAdded = "Not Added"
        case added = "In Project"
        var id: String { rawValue }
    }
    // Default to the full pool so this view never looks empty.
    @State private var scope: Scope = .all
    @State private var confirmClear = false

    private let columns = [GridItem(.adaptive(minimum: 130, maximum: 200), spacing: 8)]

    private var pool: [MediaItem] {
        let all = store.poolItems(forProject: projectID)
        switch scope {
        case .all: return all
        case .added: return all.filter { $0.projectIDs.contains(projectID) }
        case .notAdded: return all.filter { !$0.projectIDs.contains(projectID) }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            if pool.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 8) {
                        ForEach(pool) { item in
                            cell(item)
                        }
                    }
                    .padding(12)
                    .padding(.bottom, 56)   // slack so the last row stays reachable
                }
            }
        }
        .background(Theme.background)
        .onAppear { store.setVisibleItems(pool.map(\.id)) }
        .onChange(of: pool.map(\.id)) { ids in store.setVisibleItems(ids) }
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            Picker("", selection: $scope) {
                ForEach(Scope.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented).fixedSize()

            Text("\(pool.count) clips").font(.caption).foregroundStyle(Theme.textTertiary)

            Spacer()

            // Lets you wipe the current selection and curate from scratch.
            if !store.items(inProject: projectID).isEmpty {
                Button(role: .destructive) { confirmClear = true } label: {
                    Label("Start Fresh", systemImage: "arrow.counterclockwise")
                }
                .buttonStyle(.plain).foregroundStyle(Theme.textSecondary)
                .help("Remove all clips from this project so you can pick them again (files are untouched)")
            }

            Button("Select All") { store.selectAll(ids: pool.map(\.id)) }
                .buttonStyle(.plain).foregroundStyle(Theme.textSecondary)
                .disabled(pool.isEmpty)

            if !store.selection.isEmpty {
                Button { store.clearSelection() } label: { Text("Clear") }
                    .buttonStyle(.plain).foregroundStyle(Theme.textSecondary)

                Button {
                    store.addItems(store.selection, toProject: projectID)
                    store.clearSelection()
                } label: {
                    Label("Add to Project (\(store.selection.count))", systemImage: "plus.circle.fill")
                }
                .buttonStyle(.borderedProminent).tint(Theme.accent).controlSize(.small)

                if scope != .notAdded {
                    Button(role: .destructive) {
                        store.removeItems(store.selection, fromProject: projectID)
                        store.clearSelection()
                    } label: { Label("Remove", systemImage: "minus.circle") }
                    .buttonStyle(.bordered).controlSize(.small)
                }
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
        .background(Theme.surfaceRaised)
        .overlay(alignment: .bottom) { Divider().overlay(Theme.stroke) }
        .confirmationDialog("Remove all clips from this project?",
                            isPresented: $confirmClear, titleVisibility: .visible) {
            Button("Remove All", role: .destructive) {
                store.clearProjectMembers(projectID)
                store.clearSelection()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("The project's sources and footage stay put — only the project's selection is cleared, so you can pick clips again. No files are deleted.")
        }
    }

    private func cell(_ item: MediaItem) -> some View {
        let inProject = item.projectIDs.contains(projectID)
        return MediaThumbnailView(item: item, isSelected: store.selection.contains(item.id))
            .overlay(alignment: .bottomTrailing) {
                if inProject {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(Theme.background, Theme.online)
                        .padding(6)
                }
            }
            .opacity(inProject && scope == .all ? 0.65 : 1)
            .mediaDragSource(itemID: item.id, orderedIDs: pool.map(\.id), store: store)
            .contextMenu {
                if inProject {
                    Button("Remove from Project", role: .destructive) {
                        store.removeItems([item.id], fromProject: projectID)
                    }
                } else {
                    Button("Add to Project") {
                        store.addItems([item.id], toProject: projectID)
                    }
                }
                Divider()
                MediaContextMenu(item: item)
            }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: scope == .notAdded ? "checkmark.circle" : "externaldrive")
                .font(.system(size: 38)).foregroundStyle(Theme.textTertiary)
            Text(scope == .notAdded
                 ? "Everything from these sources is already in the project"
                 : "No media from this project's sources yet")
                .foregroundStyle(Theme.textSecondary)
            if store.poolItems(forProject: projectID).isEmpty {
                Text("Add a source in the project header to bring footage in.")
                    .font(.caption).foregroundStyle(Theme.textTertiary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Flagged triage

private struct FlaggedTriageView: View {
    @EnvironmentObject private var store: LibraryStore
    let projectID: UUID
    let items: [MediaItem]

    var body: some View {
        VStack(spacing: 0) {
            if !store.selection.isEmpty { triageBar }
            if items.isEmpty {
                allClearState
            } else {
                List(items) { item in
                    FlaggedRow(item: item, isSelected: store.selection.contains(item.id))
                        .listRowBackground(Theme.background)
                        .contentShape(Rectangle())
                        .onTapGesture { toggle(item) }
                        .contextMenu { MediaContextMenu(item: item) }
                }
                .listStyle(.inset)
                .scrollContentBackground(.hidden)
            }
        }
        .background(Theme.background)
    }

    private var allClearState: some View {
        VStack(spacing: 10) {
            Image(systemName: "checkmark.seal").font(.system(size: 40)).foregroundStyle(Theme.online)
            Text("No flagged clips").foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var triageBar: some View {
        HStack(spacing: 12) {
            Text("\(store.selection.count) selected")
                .font(.callout.weight(.medium)).foregroundStyle(Theme.textPrimary)
            Divider().frame(height: 16).overlay(Theme.stroke)
            Button {
                store.setReviewState(.approved, for: store.selection)
                store.clearSelection()
            } label: { Label("Approve", systemImage: "checkmark.circle") }
            Button(role: .destructive) {
                store.setReviewState(.discarded, for: store.selection)
                store.clearSelection()
            } label: { Label("Discard", systemImage: "trash.slash") }
            Button {
                store.removeItems(store.selection, fromProject: projectID)
                store.clearSelection()
            } label: { Label("Remove from Project", systemImage: "folder.badge.minus") }
            Spacer()
            Button { store.clearSelection() } label: { Label("Clear", systemImage: "xmark") }
                .foregroundStyle(Theme.textSecondary)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 14).padding(.vertical, 8)
        .background(Theme.surfaceRaised)
        .overlay(alignment: .bottom) { Divider().overlay(Theme.stroke) }
    }

    private func toggle(_ item: MediaItem) {
        store.handleSelect(item.id, in: items.map(\.id))
    }
}

private struct FlaggedRow: View {
    @EnvironmentObject private var store: LibraryStore
    let item: MediaItem
    let isSelected: Bool
    @State private var thumb: NSImage?

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(isSelected ? Theme.accent : Theme.textTertiary)
            Group {
                if let thumb {
                    Image(nsImage: thumb).resizable().scaledToFill()
                } else { ShimmerView() }
            }
            .frame(width: 72, height: 48)
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .opacity(item.isDiscarded ? 0.4 : 1)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(item.filename).foregroundStyle(Theme.textPrimary).lineLimit(1)
                    if item.isDiscarded {
                        Text("Discarded").font(.caption2)
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(Capsule().fill(Theme.offline.opacity(0.3)))
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
                FlowLayout(spacing: 4) {
                    ForEach(Array(item.qualityFlags).sorted { $0.rawValue < $1.rawValue }, id: \.self) { flag in
                        Label(flag.displayName, systemImage: flag.symbolName)
                            .font(.caption2)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Capsule().fill((flag.isMistake ? Color.red : Theme.accent).opacity(0.22)))
                            .foregroundStyle(Theme.textPrimary)
                    }
                }
            }
            Spacer()
            Text(item.formattedDuration ?? item.captureDate?.shortDate ?? "")
                .font(.caption).foregroundStyle(Theme.textTertiary)
        }
        .padding(.vertical, 4)
        .task(id: item.id) { thumb = await ThumbnailService.shared.thumbnail(for: item) }
    }
}

// MARK: - Content grouping

private struct ContentGroupView: View {
    @EnvironmentObject private var store: LibraryStore
    let items: [MediaItem]

    private let columns = [GridItem(.adaptive(minimum: 130, maximum: 200), spacing: 8)]

    private var groups: [(tag: ContentTag, items: [MediaItem])] {
        ContentTag.allCases.compactMap { tag in
            let matching = items.filter { $0.effectiveContentTags.contains(tag) }
            return matching.isEmpty ? nil : (tag, matching)
        }
    }

    var body: some View {
        let groups = self.groups
        if groups.isEmpty {
            VStack(spacing: 10) {
                Image(systemName: "tag.slash").font(.system(size: 40)).foregroundStyle(Theme.textTertiary)
                Text("No content tags yet").foregroundStyle(Theme.textSecondary)
                Text("Run analysis, or add an API key to enrich tags.")
                    .font(.caption).foregroundStyle(Theme.textTertiary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 20, pinnedViews: [.sectionHeaders]) {
                    ForEach(groups, id: \.tag) { group in
                        Section {
                            LazyVGrid(columns: columns, spacing: 8) {
                                ForEach(group.items) { item in
                                    MediaThumbnailView(item: item, isSelected: store.selection.contains(item.id))
                                        .mediaDragSource(itemID: item.id,
                                                         orderedIDs: group.items.map(\.id), store: store)
                                        .contextMenu { MediaContextMenu(item: item) }
                                }
                            }
                            .padding(.horizontal, 16)
                        } header: {
                            HStack(spacing: 8) {
                                Label(group.tag.displayName, systemImage: group.tag.symbolName)
                                    .font(.headline).foregroundStyle(Theme.textPrimary)
                                Spacer()
                                Text("\(group.items.count)").font(.caption).foregroundStyle(Theme.textTertiary)
                            }
                            .padding(.horizontal, 16).padding(.vertical, 8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Theme.background.opacity(0.96))
                        }
                    }
                }
                .padding(.vertical, 12)
            }
        }
    }
}

/// A single ordered project row: thumbnail + filename + key metadata.
private struct ProjectRow: View {
    @EnvironmentObject private var store: LibraryStore
    let item: MediaItem
    @State private var thumb: NSImage?

    var body: some View {
        HStack(spacing: 12) {
            Group {
                if let thumb { Image(nsImage: thumb).resizable().scaledToFill() }
                else { ShimmerView() }
            }
            .frame(width: 72, height: 48)
            .clipShape(RoundedRectangle(cornerRadius: 4))

            VStack(alignment: .leading, spacing: 2) {
                Text(item.filename).foregroundStyle(Theme.textPrimary).lineLimit(1)
                HStack(spacing: 8) {
                    Label(item.kind.displayName, systemImage: item.kind == .video ? "video" : "photo")
                    if let d = item.formattedDuration { Text(d) }
                    if !item.qualityFlags.isEmpty {
                        Label("\(item.qualityFlags.count)", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(Theme.accent)
                    }
                }
                .font(.caption).foregroundStyle(Theme.textTertiary)
            }
            Spacer()
            Text(item.captureDate?.shortDate ?? "").font(.caption).foregroundStyle(Theme.textTertiary)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture { store.selection = [item.id]; store.detailItemID = item.id }
        .task(id: item.id) { thumb = await ThumbnailService.shared.thumbnail(for: item) }
    }
}
