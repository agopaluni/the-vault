//
//  IngestionService.swift
//  The Vault
//
//  Background indexing queue. Given a Source, it walks the directory tree,
//  filters to known media types, extracts metadata in parallel batches, and
//  streams results back to the delegate (the LibraryStore). Geocoding is kicked
//  off opportunistically after items land so the UI isn't blocked on network.
//
//  The original files are only ever READ — never moved or modified.
//

import Foundation

protocol IngestionServiceDelegate: AnyObject {
    func ingestion(_ service: IngestionService, didIndex batch: [MediaItem])
    func ingestion(_ service: IngestionService, didProgress fraction: Double, status: String)
    func ingestion(_ service: IngestionService, didGeocode itemID: UUID, name: String)
    func ingestion(_ service: IngestionService, didReport message: String)
    func ingestionDidFinish(_ service: IngestionService)
}

final class IngestionService {
    weak var delegate: IngestionServiceDelegate?

    private let queue = DispatchQueue(label: "com.thevault.ingestion", qos: .utility)
    private let batchSize = 40

    /// Index a source. `existingPaths` lets us skip already-indexed files.
    func index(source: Source, existingPaths: Set<String>) {
        queue.async { [weak self] in
            guard let self else { return }
            self.walkAndIndex(source: source, existingPaths: existingPaths)
        }
    }

    private func walkAndIndex(source: Source, existingPaths: Set<String>) {
        let fm = FileManager.default

        // Prefer direct access (this app is not sandboxed). Fall back to a
        // security-scoped bookmark only if the direct path can't be listed.
        var root = source.url
        var scopedURL: URL?
        let directlyReadable = (try? fm.contentsOfDirectory(atPath: root.path)) != nil
        if !directlyReadable, let bookmark = source.bookmarkData {
            var stale = false
            if let resolved = try? URL(resolvingBookmarkData: bookmark,
                                       options: .withSecurityScope,
                                       relativeTo: nil,
                                       bookmarkDataIsStale: &stale) {
                _ = resolved.startAccessingSecurityScopedResource()
                scopedURL = resolved
                root = resolved
            }
        }
        defer { scopedURL?.stopAccessingSecurityScopedResource() }

        // First pass: collect candidate file URLs. An error handler catches
        // permission failures so we can tell "no media" from "no access".
        var accessError: Error?
        let keys: [URLResourceKey] = [.isRegularFileKey, .isDirectoryKey]
        let enumerator = fm.enumerator(at: root,
                                       includingPropertiesForKeys: keys,
                                       options: [.skipsHiddenFiles, .skipsPackageDescendants],
                                       errorHandler: { _, error in accessError = error; return true })

        var totalFiles = 0
        var skippedExisting = 0
        var candidates: [URL] = []
        if let enumerator {
            for case let url as URL in enumerator {
                let values = try? url.resourceValues(forKeys: [.isRegularFileKey])
                guard values?.isRegularFile == true else { continue }
                totalFiles += 1
                guard MetadataExtractor.kind(for: url) != nil else { continue }
                if existingPaths.contains(url.path) { skippedExisting += 1; continue }
                candidates.append(url)
            }
        }

        let total = candidates.count
        guard total > 0 else {
            // Distinguish the failure modes so the user gets an actionable hint.
            let listing = (try? fm.contentsOfDirectory(atPath: root.path)) ?? []
            if enumerator == nil || accessError != nil || (listing.isEmpty && totalFiles == 0) {
                NSLog("The Vault: cannot read \(root.path) — \(accessError?.localizedDescription ?? "no entries")")
                delegate?.ingestion(self, didReport:
                    "Couldn't read “\(source.label)”. If the footage is on an external drive or a protected folder (Desktop, Documents, Downloads), grant The Vault access in System Settings ▸ Privacy & Security ▸ Files and Folders (or Full Disk Access), then re-index.")
            } else if skippedExisting > 0 {
                delegate?.ingestion(self, didProgress: 1.0,
                                    status: "\(source.label): already indexed")
            } else {
                delegate?.ingestion(self, didReport:
                    "No supported photos or videos found in “\(source.label)” (scanned \(totalFiles) files).")
            }
            delegate?.ingestionDidFinish(self)
            return
        }

        // Second pass: extract metadata in batches, streaming to the delegate.
        var processed = 0
        var batch: [MediaItem] = []
        batch.reserveCapacity(batchSize)

        for url in candidates {
            if let item = MetadataExtractor.extract(url: url, sourceID: source.id) {
                batch.append(item)
            }
            processed += 1

            if batch.count >= batchSize || processed == total {
                let flushed = batch
                batch.removeAll(keepingCapacity: true)
                delegate?.ingestion(self, didIndex: flushed)
                scheduleGeocoding(for: flushed)
                let fraction = Double(processed) / Double(total)
                delegate?.ingestion(self, didProgress: fraction,
                                    status: "Indexing \(source.label) — \(processed)/\(total)")
            }
        }

        delegate?.ingestionDidFinish(self)
    }

    /// Reverse-geocode items that have coordinates, off the indexing path.
    private func scheduleGeocoding(for items: [MediaItem]) {
        let located = items.filter { $0.hasLocation }
        guard !located.isEmpty else { return }
        Task.detached(priority: .background) { [weak self] in
            guard let self else { return }
            for item in located {
                guard let lat = item.latitude, let lon = item.longitude else { continue }
                let name = await ReverseGeocoder.shared.name(latitude: lat, longitude: lon)
                self.delegate?.ingestion(self, didGeocode: item.id, name: name)
            }
        }
    }
}
