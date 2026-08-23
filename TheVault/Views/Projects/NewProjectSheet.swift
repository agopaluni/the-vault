//
//  NewProjectSheet.swift
//  The Vault
//
//  Create a project and attach one or more source folders. Each source can be
//  given a nickname, and duplicates (already-added folders) are rejected. All
//  media in the chosen sources populates the project; AI analysis is NOT run
//  automatically — the user triggers it later per selection / source / all.
//

import SwiftUI
import AppKit

struct NewProjectSheet: View {
    @EnvironmentObject private var store: LibraryStore
    @Environment(\.dismiss) private var dismiss

    struct PendingSource: Identifiable {
        let id = UUID()
        let url: URL
        var nickname: String
    }

    @State private var name = ""
    @State private var type: ProjectType = .vlog
    @State private var pending: [PendingSource] = []
    @State private var inlineMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("New Project")
                .font(.title3.bold())
                .foregroundStyle(Theme.textPrimary)

            nameAndType
            sourcesSection

            if let inlineMessage {
                Label(inlineMessage, systemImage: "exclamationmark.circle")
                    .font(.caption).foregroundStyle(Theme.accent)
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Create") { create() }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.accent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 480)
        .background(Theme.surface)
    }

    // MARK: Sections

    private var nameAndType: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Name").font(.caption).foregroundStyle(Theme.textSecondary)
                TextField("e.g. Tokyo Vlog", text: $name)
                    .textFieldStyle(.roundedBorder)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Type").font(.caption).foregroundStyle(Theme.textSecondary)
                Picker("Type", selection: $type) {
                    ForEach(ProjectType.allCases, id: \.self) { t in
                        Label(t.displayName, systemImage: t.symbolName).tag(t)
                    }
                }
                .labelsHidden().frame(width: 150)
            }
        }
    }

    private var sourcesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Sources").font(.caption).foregroundStyle(Theme.textSecondary)
                Spacer()
                Button { addSources() } label: { Label("Add Source…", systemImage: "plus") }
                    .controlSize(.small)
            }

            if pending.isEmpty {
                Text("Add one or more folders (SD card, SSD, drive). Their photos & videos will populate the project.")
                    .font(.caption).foregroundStyle(Theme.textTertiary)
            } else {
                VStack(spacing: 6) {
                    ForEach($pending) { $source in
                        HStack(spacing: 8) {
                            Image(systemName: "folder").foregroundStyle(Theme.accent)
                            VStack(alignment: .leading, spacing: 1) {
                                TextField("Nickname", text: $source.nickname)
                                    .textFieldStyle(.roundedBorder)
                                Text(source.url.path).font(.caption2)
                                    .foregroundStyle(Theme.textTertiary).lineLimit(1)
                            }
                            Button {
                                pending.removeAll { $0.id == source.id }
                            } label: { Image(systemName: "xmark.circle.fill") }
                                .buttonStyle(.plain).foregroundStyle(Theme.textTertiary)
                        }
                        .padding(8)
                        .cardBackground(Theme.surfaceRaised)
                    }
                }
            }
        }
    }

    // MARK: Logic

    private func addSources() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.prompt = "Add"
        guard panel.runModal() == .OK else { return }

        for url in panel.urls {
            let path = url.standardizedFileURL.path
            if pending.contains(where: { $0.url.standardizedFileURL.path == path }) {
                inlineMessage = "“\(url.lastPathComponent)” is already in this list."
                continue
            }
            let type = Source.guessMediaType(for: url)
            pending.append(PendingSource(url: url,
                                         nickname: "\(url.lastPathComponent) - \(type.defaultLabel)"))
            inlineMessage = nil
        }
    }

    private func create() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        let project = store.createProject(name: trimmed.isEmpty ? "Untitled Project" : trimmed, type: type)
        for source in pending {
            store.addSource(url: source.url,
                            label: source.nickname.trimmingCharacters(in: .whitespaces),
                            ownerProject: project.id)
        }
        store.sidebarSelection = .project(project.id)
        store.viewMode = .grid
        store.route = .browser
        dismiss()
    }
}
