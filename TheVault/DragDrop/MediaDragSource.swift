//
//  MediaDragSource.swift
//  The Vault
//
//  True multi-file drag-out, Finder-style.
//
//  SwiftUI's `.onDrag` can only vend ONE NSItemProvider, so dragging a
//  multi-selection into FCP / Premiere / Resolve only ever delivered a single
//  clip. This bridges to AppKit: a transparent overlay on each thumbnail owns
//  the left-mouse interaction and starts a real `beginDraggingSession` with one
//  NSDraggingItem per selected file.
//
//  Pasteboard order == drop order in the receiving NLE, so the URLs are handed
//  over in the user's pick order (LibraryStore.selectionOrder).
//

import SwiftUI
import AppKit

// MARK: - Long-lived drag source

/// Owns the dragging session instead of the cell view. SwiftUI recycles
/// LazyVGrid cells aggressively; if the view that began the session is torn
/// down mid-drag, AppKit can truncate what actually gets delivered. This object
/// outlives any cell and holds the pasteboard writers for the session.
final class MediaDragCoordinator: NSObject, NSDraggingSource {
    static let shared = MediaDragCoordinator()
    private var writers: [NSURL] = []

    func begin(urls: [URL], from view: NSView, event: NSEvent) {
        // Retain the writers for the life of the session.
        writers = urls.map { $0 as NSURL }

        var items: [NSDraggingItem] = []
        for (index, nsurl) in writers.enumerated() {
            let dragItem = NSDraggingItem(pasteboardWriter: nsurl)
            let icon = NSWorkspace.shared.icon(forFile: (nsurl as URL).path)
            let col = CGFloat(index % 20), row = CGFloat(index / 20)
            dragItem.setDraggingFrame(CGRect(x: col * 3, y: -row * 3, width: 64, height: 64),
                                      contents: icon)
            items.append(dragItem)
        }

        // Begin from a stable, long-lived view (the window's content view).
        let host = view.window?.contentView ?? view
        let session = host.beginDraggingSession(with: items, event: event, source: self)
        session.draggingFormation = .list
    }

    func draggingSession(_ session: NSDraggingSession,
                         sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        .copy
    }

    func draggingSession(_ session: NSDraggingSession,
                         endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        writers.removeAll()
    }
}

// MARK: - The NSView that starts the drag

final class MediaDragSourceView: NSView {
    var onSelect: ((NSEvent.ModifierFlags) -> Void)?
    var onDoubleClick: (() -> Void)?
    var urlsToDrag: (() -> [URL])?
    var isSelected: (() -> Bool)?

    private var mouseDownEvent: NSEvent?
    /// Set when a plain click lands on an already-selected clip. Applying the
    /// selection is deferred to mouseUp so a drag can carry the WHOLE selection
    /// (this is what Finder does — otherwise the click collapses it to one).
    private var pendingSelect: NSEvent.ModifierFlags?

    // Let right-clicks fall through to the SwiftUI view underneath so
    // `.contextMenu` keeps working.
    override func hitTest(_ point: NSPoint) -> NSView? {
        if let event = NSApp.currentEvent {
            switch event.type {
            case .rightMouseDown, .rightMouseUp, .rightMouseDragged:
                return nil
            case .leftMouseDown, .leftMouseUp, .leftMouseDragged:
                if event.modifierFlags.contains(.control) { return nil }   // ctrl-click = right-click
            default:
                break
            }
        }
        return super.hitTest(point)
    }

    override func mouseDown(with event: NSEvent) {
        mouseDownEvent = event
        pendingSelect = nil

        if event.clickCount == 2 {
            onDoubleClick?()
            return
        }

        let mods = event.modifierFlags
        let plainClick = !mods.contains(.command) && !mods.contains(.shift)
        if plainClick, isSelected?() == true {
            // Already part of the selection — hold off so a drag takes them all.
            pendingSelect = mods
        } else {
            onSelect?(mods)
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let down = mouseDownEvent else { return }
        // Small threshold so a sloppy click isn't treated as a drag.
        let dx = event.locationInWindow.x - down.locationInWindow.x
        let dy = event.locationInWindow.y - down.locationInWindow.y
        guard (dx * dx + dy * dy) > 12 else { return }

        // A drag is happening — never collapse the selection.
        pendingSelect = nil

        let urls = urlsToDrag?() ?? []
        guard !urls.isEmpty else { return }

        // Hand off to the long-lived coordinator so the session doesn't depend
        // on this (recyclable) cell view staying alive.
        MediaDragCoordinator.shared.begin(urls: urls, from: self, event: down)
        mouseDownEvent = nil
    }

    override func mouseUp(with event: NSEvent) {
        // Plain click on an already-selected clip with no drag → now collapse
        // the selection to just it.
        if let mods = pendingSelect { onSelect?(mods) }
        pendingSelect = nil
        mouseDownEvent = nil
    }

    func draggingSession(_ session: NSDraggingSession,
                         sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        .copy
    }

    /// Files are only ever copied/referenced — never moved from the source.
    func draggingSession(_ session: NSDraggingSession,
                         willBeginAt screenPoint: NSPoint) {}
}

// MARK: - SwiftUI bridge

private struct MediaDragSourceRepresentable: NSViewRepresentable {
    let onSelect: (NSEvent.ModifierFlags) -> Void
    let onDoubleClick: () -> Void
    let urlsToDrag: () -> [URL]
    let isSelected: () -> Bool

    func makeNSView(context: Context) -> MediaDragSourceView {
        let view = MediaDragSourceView()
        apply(to: view)
        return view
    }

    func updateNSView(_ view: MediaDragSourceView, context: Context) {
        apply(to: view)
    }

    private func apply(to view: MediaDragSourceView) {
        view.onSelect = onSelect
        view.onDoubleClick = onDoubleClick
        view.urlsToDrag = urlsToDrag
        view.isSelected = isSelected
    }
}

extension View {
    /// Adds Finder-style click-select + multi-file drag-out to a media cell.
    /// `orderedIDs` is the currently displayed order (for ⇧-range selection).
    func mediaDragSource(itemID: UUID,
                         orderedIDs: @escaping @autoclosure () -> [UUID],
                         store: LibraryStore,
                         onDoubleClick: (() -> Void)? = nil) -> some View {
        overlay(
            MediaDragSourceRepresentable(
                onSelect: { mods in
                    store.handleSelect(itemID, in: orderedIDs(), modifiers: mods)
                },
                onDoubleClick: {
                    onDoubleClick?() ?? { store.detailItemID = itemID }()
                },
                urlsToDrag: { store.dragURLs(startingFrom: itemID) },
                isSelected: { store.selection.contains(itemID) }
            )
        )
    }
}
