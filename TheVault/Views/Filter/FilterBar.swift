//
//  FilterBar.swift
//  The Vault
//
//  Top filter strip: media type, orientation, camera, format, date range,
//  location search, and tag state. Mirrors every field on MediaFilter and
//  surfaces an "active filters" count + clear button.
//

import SwiftUI

struct FilterBar: View {
    @EnvironmentObject private var store: LibraryStore
    @State private var showDatePopover = false
    @State private var draftStart = Calendar.current.date(byAdding: .month, value: -1, to: Date()) ?? Date()
    @State private var draftEnd = Date()

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                mediaTypePicker
                orientationMenu
                cameraMenu
                formatMenu
                tagStateMenu
                contentMenu
                flagMenu
                analysisMenu
                dateChip
                locationField

                if store.filter.activeCriteriaCount > 0 {
                    Button {
                        store.filter.reset()
                    } label: {
                        Label("Clear (\(store.filter.activeCriteriaCount))",
                              systemImage: "xmark.circle.fill")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.accent)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
        }
        .background(Theme.surface)
    }

    // MARK: Controls

    private var mediaTypePicker: some View {
        Picker("", selection: $store.filter.mediaType) {
            ForEach(MediaTypeFilter.allCases) { Text($0.rawValue).tag($0) }
        }
        .pickerStyle(.segmented)
        .fixedSize()
    }

    private var orientationMenu: some View {
        FilterChipMenu(title: "Orientation",
                       isActive: !store.filter.orientations.isEmpty) {
            ForEach(Orientation.allCases, id: \.self) { o in
                Toggle(isOn: binding(for: o)) {
                    Label(o.displayName, systemImage: o.symbolName)
                }
            }
        }
    }

    private var cameraMenu: some View {
        FilterChipMenu(title: "Camera",
                       isActive: !store.filter.cameraLabels.isEmpty) {
            if store.availableCameras.isEmpty {
                Text("No cameras indexed")
            }
            ForEach(store.availableCameras, id: \.self) { cam in
                Toggle(cam, isOn: setBinding(cam, keyPath: \.cameraLabels))
            }
        }
    }

    private var formatMenu: some View {
        FilterChipMenu(title: "Format",
                       isActive: !store.filter.fileFormats.isEmpty) {
            if store.availableFormats.isEmpty {
                Text("No formats indexed")
            }
            ForEach(store.availableFormats, id: \.self) { fmt in
                Toggle(fmt, isOn: setBinding(fmt, keyPath: \.fileFormats))
            }
        }
    }

    private var tagStateMenu: some View {
        FilterChipMenu(title: "Tags",
                       isActive: store.filter.tagFilter != .any || !store.filter.tagIDs.isEmpty) {
            Picker("State", selection: $store.filter.tagFilter) {
                ForEach(TagFilter.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.inline)
            Divider()
            ForEach(store.tags) { tag in
                Toggle(isOn: tagBinding(tag.id)) {
                    Label(tag.name, systemImage: "tag")
                }
            }
        }
    }

    private var contentMenu: some View {
        FilterChipMenu(title: "Content",
                       isActive: !store.filter.contentTags.isEmpty) {
            ForEach(ContentTag.allCases, id: \.self) { tag in
                Toggle(isOn: contentBinding(tag)) {
                    Label(tag.displayName, systemImage: tag.symbolName)
                }
            }
        }
    }

    private var flagMenu: some View {
        FilterChipMenu(title: "Quality",
                       isActive: store.filter.flagFilter != .any || store.filter.showDiscarded) {
            Picker("Flags", selection: $store.filter.flagFilter) {
                ForEach(FlagFilter.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.inline)
            Divider()
            Toggle("Show discarded", isOn: $store.filter.showDiscarded)
        }
    }

    private var analysisMenu: some View {
        FilterChipMenu(title: "AI",
                       isActive: store.filter.analysisFilter != .any) {
            Picker("Analysis", selection: $store.filter.analysisFilter) {
                ForEach(AnalysisFilter.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.inline)
        }
    }

    // A chip that opens a popover — DatePickers inside a Menu don't work on macOS.
    private var dateChip: some View {
        Button {
            if let range = store.filter.dateRange { draftStart = range.lowerBound; draftEnd = range.upperBound }
            showDatePopover.toggle()
        } label: {
            HStack(spacing: 4) {
                Text(dateLabel)
                Image(systemName: "chevron.down").font(.caption2)
            }
            .padding(.horizontal, 10).padding(.vertical, 5)
            .foregroundStyle(store.filter.dateRange != nil ? Theme.background : Theme.textPrimary)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(store.filter.dateRange != nil ? Theme.accent : Theme.surfaceRaised))
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showDatePopover, arrowEdge: .bottom) { datePopover }
    }

    private var datePopover: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Date Range").font(.headline).foregroundStyle(Theme.textPrimary)

            FlowLayout(spacing: 6) {
                presetButton("Today", days: 0)
                presetButton("7 Days", days: 6)
                presetButton("30 Days", days: 29)
                presetButton("90 Days", days: 89)
                Button("This Year") { applyYear() }.buttonStyle(.bordered).controlSize(.small)
            }

            Divider()
            DatePicker("From", selection: $draftStart, displayedComponents: .date)
            DatePicker("To", selection: $draftEnd, displayedComponents: .date)
                .datePickerStyle(.field)

            HStack {
                Button("Clear") {
                    store.filter.dateRange = nil
                    showDatePopover = false
                }
                Spacer()
                Button("Apply") {
                    store.filter.dateRange = min(draftStart, draftEnd)...max(draftStart, draftEnd)
                    showDatePopover = false
                }
                .buttonStyle(.borderedProminent).tint(Theme.accent)
            }
        }
        .padding(16)
        .frame(width: 300)
    }

    private func presetButton(_ title: String, days: Int) -> some View {
        Button(title) {
            let end = Date()
            let start = Calendar.current.date(byAdding: .day, value: -days, to: end) ?? end
            store.filter.dateRange = start...end
            showDatePopover = false
        }
        .buttonStyle(.bordered).controlSize(.small)
    }

    private func applyYear() {
        let cal = Calendar.current
        let now = Date()
        let start = cal.date(from: cal.dateComponents([.year], from: now)) ?? now
        store.filter.dateRange = start...now
        showDatePopover = false
    }

    private var dateLabel: String {
        guard let range = store.filter.dateRange else { return "Date" }
        return "\(range.lowerBound.shortDate) – \(range.upperBound.shortDate)"
    }

    private var locationField: some View {
        HStack(spacing: 5) {
            Image(systemName: "mappin.and.ellipse")
                .foregroundStyle(Theme.textTertiary)
            TextField("Location", text: $store.filter.locationQuery)
                .textFieldStyle(.plain)
                .frame(width: 130)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .cardBackground(Theme.surfaceRaised)
    }

    // MARK: Bindings

    private func binding(for o: Orientation) -> Binding<Bool> {
        Binding(
            get: { store.filter.orientations.contains(o) },
            set: { on in
                if on { store.filter.orientations.insert(o) }
                else { store.filter.orientations.remove(o) }
            })
    }

    private func setBinding(_ value: String,
                            keyPath: WritableKeyPath<MediaFilter, Set<String>>) -> Binding<Bool> {
        Binding(
            get: { store.filter[keyPath: keyPath].contains(value) },
            set: { on in
                if on { store.filter[keyPath: keyPath].insert(value) }
                else { store.filter[keyPath: keyPath].remove(value) }
            })
    }

    private func contentBinding(_ tag: ContentTag) -> Binding<Bool> {
        Binding(
            get: { store.filter.contentTags.contains(tag) },
            set: { on in
                if on { store.filter.contentTags.insert(tag) }
                else { store.filter.contentTags.remove(tag) }
            })
    }

    private func tagBinding(_ id: UUID) -> Binding<Bool> {
        Binding(
            get: { store.filter.tagIDs.contains(id) },
            set: { on in
                if on { store.filter.tagIDs.insert(id) }
                else { store.filter.tagIDs.remove(id) }
            })
    }
}

/// A small labeled menu chip that highlights when its filter is active.
private struct FilterChipMenu<Content: View>: View {
    let title: String
    let isActive: Bool
    @ViewBuilder var content: Content

    var body: some View {
        Menu {
            content
        } label: {
            HStack(spacing: 4) {
                Text(title)
                Image(systemName: "chevron.down").font(.caption2)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .foregroundStyle(isActive ? Theme.background : Theme.textPrimary)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isActive ? Theme.accent : Theme.surfaceRaised)
            )
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }
}
