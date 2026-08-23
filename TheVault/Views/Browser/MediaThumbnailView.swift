//
//  MediaThumbnailView.swift
//  The Vault
//
//  A single grid cell: async-loaded thumbnail with a shimmer placeholder, plus
//  overlay badges (date/time, location pill, duration, camera/type icon).
//  Selection ring + drag-out are handled here.
//

import SwiftUI

struct MediaThumbnailView: View {
    let item: MediaItem
    let isSelected: Bool

    @State private var image: NSImage?
    @State private var didFail = false

    var body: some View {
        ZStack {
            thumbnail
            overlays
            selectionRing
        }
        .aspectRatio(1, contentMode: .fill)
        .clipShape(RoundedRectangle(cornerRadius: Theme.thumbnailCorner, style: .continuous))
        .contentShape(Rectangle())
        .task(id: item.id) { await load() }
    }

    // MARK: Image

    @ViewBuilder
    private var thumbnail: some View {
        GeometryReader { geo in
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()
            } else if didFail {
                ZStack {
                    Theme.surfaceRaised
                    Image(systemName: item.kind == .video ? "video.slash" : "photo")
                        .font(.title2)
                        .foregroundStyle(Theme.textTertiary)
                }
            } else {
                ShimmerView()
            }
        }
    }

    private func load() async {
        image = nil
        didFail = false
        if let img = await ThumbnailService.shared.thumbnail(for: item) {
            image = img
        } else {
            didFail = true
        }
    }

    // MARK: Overlays

    private var overlays: some View {
        VStack {
            HStack(alignment: .top) {
                // Type / camera icon
                Image(systemName: item.kind == .video ? "video.fill" : "camera.fill")
                    .font(.caption2)
                    .padding(4)
                    .background(.black.opacity(0.45), in: Capsule())
                if !item.qualityFlags.isEmpty { flagBadge }
                Spacer()
                if let duration = item.formattedDuration {
                    badge(duration, systemImage: "play.fill")
                }
            }
            Spacer()
            HStack(alignment: .bottom) {
                if let date = item.captureDate {
                    badge(date.timeOnly)
                }
                Spacer()
                if let location = item.locationName {
                    locationPill(location)
                }
            }
        }
        .padding(6)
        .foregroundStyle(.white)
    }

    /// Warning badge summarizing quality flags. Red when the clip is likely a
    /// mistake, amber for technical-quality issues only.
    private var flagBadge: some View {
        let flags = item.qualityFlags
        let isMistake = flags.contains { $0.isMistake }
        return HStack(spacing: 2) {
            Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 8))
            Text("\(flags.count)").font(.system(size: 9, weight: .bold))
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
        .background((isMistake ? Color.red : Theme.accent).opacity(0.9), in: Capsule())
        .foregroundStyle(isMistake ? .white : .black)
        .help(flags.map(\.displayName).sorted().joined(separator: ", "))
    }

    private func badge(_ text: String, systemImage: String? = nil) -> some View {
        HStack(spacing: 3) {
            if let systemImage { Image(systemName: systemImage).font(.system(size: 8)) }
            Text(text).font(.system(size: 10, weight: .medium))
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 2)
        .background(.black.opacity(0.5), in: Capsule())
    }

    private func locationPill(_ text: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: "mappin").font(.system(size: 8))
            Text(text).font(.system(size: 10, weight: .medium)).lineLimit(1)
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 2)
        .frame(maxWidth: 130, alignment: .leading)
        .background(Theme.accent.opacity(0.85), in: Capsule())
        .foregroundStyle(.black)
    }

    private var selectionRing: some View {
        RoundedRectangle(cornerRadius: Theme.thumbnailCorner, style: .continuous)
            .strokeBorder(isSelected ? Theme.accent : .clear, lineWidth: 3)
    }
}

/// A subtle animated shimmer placeholder used while thumbnails load.
struct ShimmerView: View {
    @State private var phase: CGFloat = -1

    var body: some View {
        Theme.surfaceRaised
            .overlay(
                GeometryReader { geo in
                    LinearGradient(
                        colors: [.clear, .white.opacity(0.06), .clear],
                        startPoint: .leading, endPoint: .trailing)
                    .frame(width: geo.size.width * 1.5)
                    .offset(x: phase * geo.size.width * 1.5)
                }
            )
            .onAppear {
                withAnimation(.linear(duration: 1.1).repeatForever(autoreverses: false)) {
                    phase = 1.2
                }
            }
            .clipped()
    }
}
