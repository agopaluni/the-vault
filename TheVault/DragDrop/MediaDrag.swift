//
//  MediaDrag.swift
//  The Vault
//
//  Drag-out support so selected media can be dropped into Finder, FCP,
//  Lightroom, Premiere, or any other app. Two complementary mechanisms:
//
//  1. `itemProvider(for:)` — vends the REAL on-disk file URL via NSItemProvider
//     for SwiftUI `.onDrag`. Receiving apps get a reference to the original
//     file (no copy, original untouched). Best for FCP/Lightroom "import from".
//
//  2. `MediaFilePromiseProvider` — an NSFilePromiseProvider for AppKit-driven
//     multi-item drags. When a destination requests the promise, we copy the
//     original to the drop location. We READ the original and write a copy at
//     the destination — the source file is never moved or modified.
//

import AppKit
import UniformTypeIdentifiers

enum MediaDrag {

    /// NSItemProvider that exposes the file's real URL to the drag session.
    static func itemProvider(for item: MediaItem) -> NSItemProvider {
        let provider = NSItemProvider()
        let url = item.url
        let typeID = (UTType(filenameExtension: url.pathExtension)
                      ?? .data).identifier

        provider.registerFileRepresentation(forTypeIdentifier: typeID,
                                             fileOptions: [],
                                             visibility: .all) { completion in
            // Hand back the ORIGINAL url; `false` => system must not move it.
            completion(url, false, nil)
            return nil
        }
        provider.suggestedName = item.filename
        return provider
    }

    static func itemProviders(for items: [MediaItem]) -> [NSItemProvider] {
        items.map { itemProvider(for: $0) }
    }
}

/// File-promise provider for AppKit drag sources that want to promise files.
/// Copies the original to the drop destination on demand (non-destructive).
final class MediaFilePromiseProvider: NSFilePromiseProvider {
    /// The original file this promise represents.
    var sourceURL: URL?

    convenience init(item: MediaItem) {
        let typeID = (UTType(filenameExtension: item.url.pathExtension) ?? .data).identifier
        self.init(fileType: typeID, delegate: PromiseDelegate.shared)
        self.sourceURL = item.url
        self.userInfo = item.path
    }
}

/// Shared delegate that performs the copy when a destination accepts a promise.
final class PromiseDelegate: NSObject, NSFilePromiseProviderDelegate {
    static let shared = PromiseDelegate()

    private let ioQueue = OperationQueue()

    func filePromiseProvider(_ provider: NSFilePromiseProvider,
                             fileNameForType fileType: String) -> String {
        if let path = provider.userInfo as? String {
            return (path as NSString).lastPathComponent
        }
        return "media"
    }

    func filePromiseProvider(_ provider: NSFilePromiseProvider,
                             writePromiseTo url: URL,
                             completionHandler: @escaping (Error?) -> Void) {
        guard let path = provider.userInfo as? String else {
            completionHandler(nil); return
        }
        let source = URL(fileURLWithPath: path)
        ioQueue.addOperation {
            do {
                // Copy a NEW file to the drop destination; original is read-only here.
                if FileManager.default.fileExists(atPath: url.path) {
                    try FileManager.default.removeItem(at: url)
                }
                try FileManager.default.copyItem(at: source, to: url)
                completionHandler(nil)
            } catch {
                completionHandler(error)
            }
        }
    }

    func operationQueue(for provider: NSFilePromiseProvider) -> OperationQueue { ioQueue }
}
