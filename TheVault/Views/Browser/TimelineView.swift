//
//  TimelineView.swift
//  The Vault
//
//  Vertical scrollable timeline grouping the filtered media by capture day.
//  Each day is a sticky header (with an inline map pin when any item that day
//  has GPS) above a horizontal-wrapping row of thumbnails.
//

import SwiftUI

struct TimelineView: View {
    @EnvironmentObject private var store: LibraryStore

    private struct DayGroup: Identifiable {
        let id: Date
        let items: [MediaItem]
        var hasLocation: Bool { items.contains { $0.hasLocation } }
        var primaryLocation: String? { items.first { $0.locationName != nil }?.locationName }
    }

    private var groups: [DayGroup] {
        let items = store.filteredItems
        let buckets = Dictionary(grouping: items) { ($0.captureDate ?? .distantPast).dayStart }
        return buckets
            .map { DayGroup(id: $0.key, items: $0.value) }
            .sorted { store.filter.sortDirection == .ascending ? $0.id < $1.id : $0.id > $1.id }
    }

    private let columns = [GridItem(.adaptive(minimum: 130, maximum: 200), spacing: 8)]

    /// Shown when a project is selected so you can flip between the curated
    /// selection and every clip from the project's sources.
    @ViewBuilder
    private var scopeBar: some View {
        if case .project(let pid) = store.sidebarSelection {
            HStack(spacing: 10) {
                Picker("", selection: $store.projectScope) {
                    ForEach(ProjectScope.allCases) { scope in
                        Label(scope.rawValue, systemImage: scope.symbolName).tag(scope)
                    }
                }
                .pickerStyle(.segmented)
                .fixedSize()

                Text("\(store.filteredItems.count) clips")
                    .font(.caption).foregroundStyle(Theme.textTertiary)

                Spacer()

                if store.projectScope == .sourceMedia, !store.selection.isEmpty {
                    Button {
                        store.addItems(store.selection, toProject: pid)
                        store.clearSelection()
                    } label: {
                        Label("Add to Project (\(store.selection.count))",
                              systemImage: "plus.circle.fill")
                    }
                    .buttonStyle(.borderedProminent).tint(Theme.accent).controlSize(.small)
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 8)
            .background(Theme.surfaceRaised)
            .overlay(alignment: .bottom) { Divider().overlay(Theme.stroke) }
        }
    }

    var body: some View {
        // Computed ONCE per render — timeline order (day groups flattened) is
        // both the ⇧-range order and what ⌘A selects.
        let groups = self.groups
        let orderedIDs = groups.flatMap { $0.items.map(\.id) }

        return VStack(spacing: 0) {
            scopeBar
            timelineContent(groups: groups, orderedIDs: orderedIDs)
        }
        .background(Theme.background)
        .onAppear { store.setVisibleItems(orderedIDs) }
        .onChange(of: orderedIDs) { ids in store.setVisibleItems(ids) }
    }

    @ViewBuilder
    private func timelineContent(groups: [DayGroup], orderedIDs: [UUID]) -> some View {
        if groups.isEmpty {
            EmptyBrowserState()
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 24, pinnedViews: [.sectionHeaders]) {
                    ForEach(groups) { group in
                        Section {
                            LazyVGrid(columns: columns, spacing: 8) {
                                ForEach(group.items) { item in
                                    cell(item, orderedIDs: orderedIDs)
                                }
                            }
                            .padding(.horizontal, 16)
                        } header: {
                            header(for: group)
                        }
                    }
                }
                .padding(.vertical, 12)
                .padding(.bottom, 56)   // slack so the last row clears the status bar
            }
            .background(Theme.background)
        }
    }

    private func cell(_ item: MediaItem, orderedIDs: [UUID]) -> some View {
        MediaThumbnailView(item: item, isSelected: store.selection.contains(item.id))
            .mediaDragSource(itemID: item.id, orderedIDs: orderedIDs, store: store)
            .contextMenu { MediaContextMenu(item: item) }
    }

    private func header(for group: DayGroup) -> some View {
        HStack(spacing: 8) {
            Text(group.id == .distantPast ? "No Date" : group.id.dayHeader)
                .font(.headline)
                .foregroundStyle(Theme.textPrimary)
            if group.hasLocation, let loc = group.primaryLocation {
                Label(loc, systemImage: "mappin.circle.fill")
                    .font(.caption)
                    .foregroundStyle(Theme.accent)
            }
            Spacer()
            Text("\(group.items.count)")
                .font(.caption)
                .foregroundStyle(Theme.textTertiary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.background.opacity(0.96))
    }
}
