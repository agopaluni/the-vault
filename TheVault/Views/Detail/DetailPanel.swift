//
//  DetailPanel.swift
//  The Vault
//
//  Right-side sliding inspector for the focused item: full-res photo preview
//  with zoom, inline video playback with scrubbing, a full metadata table,
//  and an inline tag + project editor.
//

import SwiftUI
import AVKit

struct DetailPanel: View {
    @EnvironmentObject private var store: LibraryStore

    private var item: MediaItem? {
        store.detailItemID.flatMap { store.item($0) }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(Theme.stroke)
            if let item {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        PreviewArea(item: item)
                            .frame(height: 240)
                            .frame(maxWidth: .infinity)
                            .background(Color.black)
                            .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius))

                        AnalysisSection(item: item)
                        ContentTagEditor(item: item)
                        TagEditor(item: item)
                        ProjectMembership(item: item)
                        MetadataTable(item: item)
                        actions(for: item)
                    }
                    .padding(14)
                }
            } else {
                Spacer()
                Text("No selection").foregroundStyle(Theme.textTertiary)
                Spacer()
            }
        }
        .background(Theme.surface)
    }

    private var header: some View {
        HStack {
            Text(item?.filename ?? "Preview")
                .font(.headline)
                .lineLimit(1)
                .foregroundStyle(Theme.textPrimary)
            Spacer()
            Button {
                store.detailItemID = nil
            } label: { Image(systemName: "sidebar.right") }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.textSecondary)
                .help("Close panel")
        }
        .padding(12)
    }

    private func actions(for item: MediaItem) -> some View {
        HStack {
            Button {
                NSWorkspace.shared.reveal([item.url])
            } label: { Label("Reveal", systemImage: "magnifyingglass") }
            Button {
                NSPasteboard.general.writeFileURLs([item.url])
            } label: { Label("Copy Path", systemImage: "doc.on.clipboard") }
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }
}

// MARK: - Preview

private struct PreviewArea: View {
    let item: MediaItem

    var body: some View {
        switch item.kind {
        case .photo: PhotoPreview(item: item)
        case .video: VideoPreview(url: item.url)
        }
    }
}

/// Full-res photo with pinch / scroll zoom.
private struct PhotoPreview: View {
    let item: MediaItem
    @State private var image: NSImage?
    @State private var zoom: CGFloat = 1

    var body: some View {
        ZStack {
            if let image {
                ScrollView([.horizontal, .vertical]) {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                        .scaleEffect(zoom)
                        .gesture(MagnificationGesture()
                            .onChanged { zoom = max(1, min(5, $0)) })
                        .frame(minWidth: 0, minHeight: 0)
                }
                .overlay(alignment: .bottomTrailing) {
                    if zoom > 1 {
                        Button("Reset Zoom") { withAnimation { zoom = 1 } }
                            .controlSize(.mini)
                            .padding(6)
                    }
                }
            } else {
                ProgressView()
            }
        }
        .task(id: item.id) {
            image = await ThumbnailService.shared.thumbnail(for: item)
            // For full-res, load the original directly if readable.
            if let full = NSImage(contentsOf: item.url) { image = full }
        }
    }
}

/// Inline AVKit player with native scrubbing controls.
///
/// Wraps AppKit's `AVPlayerView` directly rather than SwiftUI's `VideoPlayer`.
/// The SwiftUI wrapper crashes on some macOS builds while instantiating its
/// generic metadata inside `_AVKit_SwiftUI` (abort in `getSuperclassMetadata`);
/// `AVPlayerView` avoids that code path entirely.
private struct VideoPreview: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.controlsStyle = .inline
        view.videoGravity = .resizeAspect
        view.player = AVPlayer(url: url)
        context.coordinator.currentURL = url
        return view
    }

    func updateNSView(_ view: AVPlayerView, context: Context) {
        // Switch the player only when the selected clip actually changes.
        if context.coordinator.currentURL != url {
            view.player?.pause()
            view.player = AVPlayer(url: url)
            context.coordinator.currentURL = url
        }
    }

    static func dismantleNSView(_ view: AVPlayerView, coordinator: Coordinator) {
        view.player?.pause()
        view.player = nil
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var currentURL: URL?
    }
}
