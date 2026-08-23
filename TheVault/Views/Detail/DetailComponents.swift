//
//  DetailComponents.swift
//  The Vault
//
//  Sub-views for the detail panel: the metadata table, inline tag editor with
//  quick-create, and project membership editor.
//

import SwiftUI

// MARK: - Metadata table

struct MetadataTable: View {
    let item: MediaItem

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel("Metadata")
            VStack(spacing: 0) {
                row("Type", item.kind.displayName)
                row("Date", item.captureDate?.mediumDateTime ?? "Unknown")
                if let loc = item.locationName { row("Location", loc) }
                if item.hasLocation {
                    row("Coordinates", ReverseGeocoder.coordinateString(
                        latitude: item.latitude ?? 0, longitude: item.longitude ?? 0))
                }
                row("Camera", item.cameraLabel)
                row("Resolution", item.resolutionLabel)
                row("Orientation", item.orientation.displayName)
                if let dur = item.formattedDuration { row("Duration", dur) }
                if let fps = item.frameRate, fps > 0 {
                    row("Frame Rate", String(format: "%.0f fps", fps))
                }
                if let codec = item.codec { row("Codec", codec) }
                row("Format", item.fileFormat)
                row("File Size", item.formattedFileSize)
                row("Path", item.path, mono: true)
            }
            .cardBackground(Theme.surfaceRaised)
        }
    }

    private func row(_ key: String, _ value: String, mono: Bool = false) -> some View {
        HStack(alignment: .top) {
            Text(key)
                .font(.caption)
                .foregroundStyle(Theme.textTertiary)
                .frame(width: 86, alignment: .leading)
            Text(value)
                .font(mono ? .system(.caption, design: .monospaced) : .caption)
                .foregroundStyle(Theme.textPrimary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Theme.stroke.opacity(0.5)).frame(height: 0.5)
        }
    }
}

// MARK: - Tag editor

struct TagEditor: View {
    @EnvironmentObject private var store: LibraryStore
    let item: MediaItem
    @State private var newTagName = ""
    @State private var newTagColor = Tag.palette[0]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel("Tags")
            FlowLayout(spacing: 6) {
                ForEach(store.tags) { tag in
                    let isOn = item.tagIDs.contains(tag.id)
                    Button {
                        store.toggleTag(tag.id, on: item.id)
                    } label: {
                        HStack(spacing: 4) {
                            Circle().fill(tag.color).frame(width: 8, height: 8)
                            Text(tag.name).font(.caption)
                            if isOn { Image(systemName: "checkmark").font(.system(size: 8)) }
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            Capsule().fill(isOn ? tag.color.opacity(0.25) : Theme.surfaceRaised)
                        )
                        .overlay(Capsule().strokeBorder(isOn ? tag.color : .clear, lineWidth: 1))
                        .foregroundStyle(Theme.textPrimary)
                    }
                    .buttonStyle(.plain)
                }
            }

            HStack(spacing: 6) {
                ColorDot(selected: $newTagColor)
                TextField("New tag…", text: $newTagName)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(createTag)
                Button(action: createTag) { Image(systemName: "plus") }
                    .buttonStyle(.bordered)
                    .disabled(newTagName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    private func createTag() {
        let name = newTagName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        let tag = store.createTag(name: name, colorHex: newTagColor)
        store.applyTag(tag.id, to: [item.id])
        newTagName = ""
    }
}

/// Small color picker dot cycling through the tag palette.
private struct ColorDot: View {
    @Binding var selected: String

    var body: some View {
        Menu {
            ForEach(Tag.palette, id: \.self) { hex in
                Button {
                    selected = hex
                } label: {
                    Label(hex, systemImage: selected == hex ? "checkmark.circle.fill" : "circle.fill")
                }
            }
        } label: {
            Circle().fill(Color(hex: selected) ?? .accentColor)
                .frame(width: 16, height: 16)
                .overlay(Circle().strokeBorder(Theme.stroke))
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }
}

// MARK: - Project membership

struct ProjectMembership: View {
    @EnvironmentObject private var store: LibraryStore
    let item: MediaItem

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel("Projects")
            if store.projects.isEmpty {
                Text("No projects yet").font(.caption).foregroundStyle(Theme.textTertiary)
            }
            FlowLayout(spacing: 6) {
                ForEach(store.projects) { project in
                    let isOn = item.projectIDs.contains(project.id)
                    Button {
                        if isOn { store.removeItems([item.id], fromProject: project.id) }
                        else { store.addItems([item.id], toProject: project.id) }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: project.type.symbolName).font(.system(size: 9))
                            Text(project.name).font(.caption)
                            if isOn { Image(systemName: "checkmark").font(.system(size: 8)) }
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(isOn ? Theme.accent.opacity(0.25) : Theme.surfaceRaised))
                        .overlay(Capsule().strokeBorder(isOn ? Theme.accent : .clear, lineWidth: 1))
                        .foregroundStyle(Theme.textPrimary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

// MARK: - AI analysis readout

struct AnalysisSection: View {
    @EnvironmentObject private var store: LibraryStore
    let item: MediaItem

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                SectionLabel("Analysis")
                Spacer()
                if store.analyzableCount([item.id], force: true) > 0 {
                    Button {
                        store.analyze([item.id], force: item.analysis != nil)
                    } label: {
                        Text(item.analysis == nil ? "Analyze" : "Re-analyze").font(.caption2)
                    }
                    .buttonStyle(.plain).foregroundStyle(Theme.accent)
                    .disabled(store.isAnalyzing)
                }
            }

            if let analysis = item.analysis {
                if !analysis.flags.isEmpty {
                    FlowLayout(spacing: 6) {
                        ForEach(Array(analysis.flags).sorted { $0.rawValue < $1.rawValue }, id: \.self) { flag in
                            chip(flag.displayName, symbol: flag.symbolName,
                                 color: flag.isMistake ? .red : Theme.accent)
                        }
                    }
                } else {
                    Label("No quality issues detected", systemImage: "checkmark.seal")
                        .font(.caption).foregroundStyle(Theme.online)
                }

                if let scene = analysis.sceneDescription, !scene.isEmpty {
                    Text(scene).font(.caption).foregroundStyle(Theme.textSecondary)
                }

                Text(sourceLine(analysis))
                    .font(.caption2).foregroundStyle(Theme.textTertiary)
            } else {
                Text("Not analyzed yet. Run analysis to flag quality issues and tag content.")
                    .font(.caption).foregroundStyle(Theme.textTertiary)
            }
        }
    }

    private func sourceLine(_ a: MediaAnalysis) -> String {
        switch a.source {
        case .onDevice: return "On-device analysis"
        case .api: return "AI: \(a.apiModel ?? "Claude")"
        case .hybrid: return "On-device + \(a.apiModel ?? "Claude")"
        }
    }

    private func chip(_ text: String, symbol: String, color: Color) -> some View {
        Label(text, systemImage: symbol)
            .font(.caption2)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(Capsule().fill(color.opacity(0.22)))
            .foregroundStyle(Theme.textPrimary)
    }
}

// MARK: - Content-tag editor (manual add/remove)

struct ContentTagEditor: View {
    @EnvironmentObject private var store: LibraryStore
    let item: MediaItem

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel("Content Tags")
            ForEach(ContentTag.Group.allCases, id: \.self) { group in
                VStack(alignment: .leading, spacing: 4) {
                    Text(group.rawValue).font(.caption2).foregroundStyle(Theme.textTertiary)
                    FlowLayout(spacing: 6) {
                        ForEach(ContentTag.allCases.filter { $0.group == group }, id: \.self) { tag in
                            tagToggle(tag)
                        }
                    }
                }
            }
        }
    }

    private func tagToggle(_ tag: ContentTag) -> some View {
        let isOn = item.effectiveContentTags.contains(tag)
        return Button {
            store.setContentTag(tag, on: item.id, present: !isOn)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: tag.symbolName).font(.system(size: 9))
                Text(tag.displayName).font(.caption)
                if isOn { Image(systemName: "checkmark").font(.system(size: 8)) }
            }
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(Capsule().fill(isOn ? Theme.accent.opacity(0.25) : Theme.surfaceRaised))
            .overlay(Capsule().strokeBorder(isOn ? Theme.accent : .clear, lineWidth: 1))
            .foregroundStyle(Theme.textPrimary)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Shared bits

struct SectionLabel: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text.uppercased())
            .font(.caption2.weight(.semibold))
            .foregroundStyle(Theme.textTertiary)
            .tracking(0.6)
    }
}
