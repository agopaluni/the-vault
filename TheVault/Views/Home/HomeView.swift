//
//  HomeView.swift
//  The Vault
//
//  Projects-first landing screen. On launch the app opens here with three
//  choices: create a new project, browse existing projects, or open the full
//  video browser.
//

import SwiftUI
import AppKit

struct HomeView: View {
    @EnvironmentObject private var store: LibraryStore
    @State private var showNewProject = false
    @State private var browsingProjects = false

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            if browsingProjects {
                ProjectBrowseView(onBack: { browsingProjects = false })
            } else {
                menu
            }
        }
        .sheet(isPresented: $showNewProject) { NewProjectSheet() }
    }

    private var menu: some View {
        VStack(spacing: 28) {
            VStack(spacing: 6) {
                Image(systemName: "film.stack")
                    .font(.system(size: 48))
                    .foregroundStyle(Theme.accent)
                Text("The Vault")
                    .font(.system(size: 34, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                Text("Media organization for filmmakers")
                    .font(.callout)
                    .foregroundStyle(Theme.textTertiary)
            }

            VStack(spacing: 12) {
                HomeButton(title: "Create a New Project",
                           subtitle: "Add sources and start logging",
                           symbol: "plus.rectangle.on.folder",
                           prominent: true) { showNewProject = true }

                HomeButton(title: "Browse Existing Projects",
                           subtitle: store.projects.isEmpty ? "No projects yet"
                                                            : "\(store.projects.count) project\(store.projects.count == 1 ? "" : "s")",
                           symbol: "square.grid.2x2",
                           disabled: store.projects.isEmpty) { browsingProjects = true }

                HomeButton(title: "Video Browser",
                           subtitle: "Browse all indexed media",
                           symbol: "photo.stack") {
                    store.sidebarSelection = .allMedia
                    store.route = .browser
                }
            }
            .frame(width: 380)
        }
        .padding(40)
    }
}

private struct HomeButton: View {
    let title: String
    let subtitle: String
    let symbol: String
    var prominent: Bool = false
    var disabled: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: symbol)
                    .font(.title2)
                    .frame(width: 30)
                    .foregroundStyle(prominent ? Theme.background : Theme.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.headline)
                    Text(subtitle).font(.caption)
                        .foregroundStyle(prominent ? Theme.background.opacity(0.7) : Theme.textTertiary)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption).opacity(0.5)
            }
            .padding(.horizontal, 16).padding(.vertical, 14)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                    .fill(prominent ? Theme.accent : Theme.surface)
            )
            .foregroundStyle(prominent ? Theme.background : Theme.textPrimary)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.45 : 1)
    }
}

/// Grid of existing projects to pick from.
private struct ProjectBrowseView: View {
    @EnvironmentObject private var store: LibraryStore
    let onBack: () -> Void

    // Packed, left-aligned adaptive grid: more columns on wider windows, tight
    // even gaps, no oversized cards.
    private let columns = [GridItem(.adaptive(minimum: 190, maximum: 230), spacing: 12,
                                    alignment: .top)]

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(Theme.stroke)
            ScrollView {
                LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
                    ForEach(store.projects) { project in
                        Button { open(project) } label: { ProjectCard(project: project) }
                            .buttonStyle(.plain)
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
    }

    private var header: some View {
        HStack {
            Button { onBack() } label: { Label("Home", systemImage: "chevron.left") }
                .buttonStyle(.plain).foregroundStyle(Theme.textSecondary)
            Spacer()
            Text("Projects").font(.headline).foregroundStyle(Theme.textPrimary)
            Spacer()
            Text("\(store.projects.count)").font(.headline).foregroundStyle(Theme.textTertiary)
                .frame(minWidth: 44, alignment: .trailing)
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
    }

    private func open(_ project: Project) {
        store.sidebarSelection = .project(project.id)
        store.viewMode = .grid
        store.route = .browser
    }
}

private struct ProjectCard: View {
    @EnvironmentObject private var store: LibraryStore
    let project: Project
    @State private var cover: NSImage?

    private var members: [MediaItem] { store.items(inProject: project.id) }
    private var flagged: Int { members.filter { !$0.qualityFlags.isEmpty }.count }
    private var accent: Color { Color(hex: project.type.accentHex) ?? Theme.accent }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            coverArea
                .frame(height: 96)
                .frame(maxWidth: .infinity)
                .clipped()

            VStack(alignment: .leading, spacing: 3) {
                Text(project.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Label(project.type.displayName, systemImage: project.type.symbolName)
                        .labelStyle(.titleAndIcon)
                    Text("· \(project.itemCount)")
                    Spacer()
                    if flagged > 0 {
                        Label("\(flagged)", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(Theme.accent)
                    }
                }
                .font(.caption2)
                .foregroundStyle(Theme.textTertiary)
                .lineLimit(1)
            }
            .padding(10)
        }
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                .strokeBorder(Theme.stroke, lineWidth: 1))
        .task(id: project.id) { await loadCover() }
    }

    @ViewBuilder
    private var coverArea: some View {
        if let cover {
            Image(nsImage: cover).resizable().scaledToFill()
        } else {
            ZStack {
                LinearGradient(colors: [accent.opacity(0.35), Theme.surfaceRaised],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                Image(systemName: project.type.symbolName)
                    .font(.title)
                    .foregroundStyle(accent)
            }
        }
    }

    private func loadCover() async {
        guard let first = members.first else { cover = nil; return }
        cover = await ThumbnailService.shared.thumbnail(for: first)
    }
}
