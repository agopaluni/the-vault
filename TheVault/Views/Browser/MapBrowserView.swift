//
//  MapBrowserView.swift
//  The Vault
//
//  Plots geotagged media on a map. Each pin represents one located item;
//  tapping a pin selects it and opens the detail panel. Items without GPS are
//  summarized in a small banner.
//

import SwiftUI
import MapKit

struct MapBrowserView: View {
    @EnvironmentObject private var store: LibraryStore
    @State private var region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 20, longitude: 0),
        span: MKCoordinateSpan(latitudeDelta: 120, longitudeDelta: 120))

    private var locatedItems: [MediaItem] {
        store.filteredItems.filter { $0.hasLocation }
    }

    var body: some View {
        ZStack(alignment: .top) {
            Map(coordinateRegion: $region,
                annotationItems: locatedItems) { item in
                MapAnnotation(coordinate: CLLocationCoordinate2D(
                    latitude: item.latitude ?? 0, longitude: item.longitude ?? 0)) {
                    MapPin(item: item, isSelected: store.detailItemID == item.id)
                        .onTapGesture {
                            store.selection = [item.id]
                            store.detailItemID = item.id
                        }
                }
            }
            .ignoresSafeArea(edges: .bottom)

            banner
        }
        .onAppear { fitRegion() }
        .onChange(of: store.sidebarSelection) { _ in fitRegion() }
        .background(Theme.background)
    }

    private var banner: some View {
        HStack {
            if case .project = store.sidebarSelection {
                Picker("", selection: $store.projectScope) {
                    ForEach(ProjectScope.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented).fixedSize()
                Divider().frame(height: 14)
            }
            Label("\(locatedItems.count) located", systemImage: "mappin.and.ellipse")
            let missing = store.filteredItems.count - locatedItems.count
            if missing > 0 {
                Text("· \(missing) without GPS")
                    .foregroundStyle(Theme.textTertiary)
            }
            Spacer()
            Button {
                fitRegion()
            } label: { Label("Fit", systemImage: "arrow.up.left.and.arrow.down.right") }
                .buttonStyle(.plain)
        }
        .font(.caption)
        .foregroundStyle(Theme.textSecondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(.ultraThinMaterial, in: Capsule())
        .padding(10)
    }

    /// Zoom to fit all located items, with a little padding.
    private func fitRegion() {
        let coords = locatedItems.compactMap { item -> CLLocationCoordinate2D? in
            guard let lat = item.latitude, let lon = item.longitude else { return nil }
            return CLLocationCoordinate2D(latitude: lat, longitude: lon)
        }
        guard !coords.isEmpty else { return }
        let lats = coords.map(\.latitude), lons = coords.map(\.longitude)
        let minLat = lats.min()!, maxLat = lats.max()!
        let minLon = lons.min()!, maxLon = lons.max()!
        let center = CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2,
                                            longitude: (minLon + maxLon) / 2)
        let span = MKCoordinateSpan(latitudeDelta: max(0.02, (maxLat - minLat) * 1.4),
                                    longitudeDelta: max(0.02, (maxLon - minLon) * 1.4))
        withAnimation { region = MKCoordinateRegion(center: center, span: span) }
    }
}

private struct MapPin: View {
    let item: MediaItem
    let isSelected: Bool

    var body: some View {
        Image(systemName: item.kind == .video ? "video.circle.fill" : "camera.circle.fill")
            .font(.title2)
            .foregroundStyle(isSelected ? Theme.accent : .white, Theme.background)
            .background(Circle().fill(isSelected ? Theme.accent : Theme.surface).padding(3))
            .shadow(radius: 2)
            .scaleEffect(isSelected ? 1.3 : 1.0)
            .animation(.spring(response: 0.3), value: isSelected)
    }
}
