//
//  VaultDatabase.swift
//  The Vault
//
//  Local, on-disk persistence for the index (sources, media items, projects,
//  tags). Stored as a versioned JSON document in Application Support. This is
//  deliberately a thin, dependency-free store with a clear seam: the
//  `VaultStore` protocol below can be re-implemented on top of Core Data /
//  SQLite for very large libraries without touching the UI layer.
//
//  Originals are never touched — this database only holds extracted metadata.
//

import Foundation

/// The complete persisted index, serialized atomically.
struct VaultSnapshot: Codable {
    // v2 adds per-item AI analysis (MediaAnalysis) + review state. Older v1
    // files still decode: the new MediaItem fields are all Optional, so a
    // missing key simply decodes to nil.
    // v3 makes project membership explicit (curated) instead of derived from
    // source ownership — LibraryStore backfills members once when loading v2.
    // v4 lets one folder back several projects (Source.projectIDs + isGlobal)
    // instead of one-scope-per-source; loading v3 merges duplicate sources and
    // the duplicate items they produced.
    var version: Int = 4
    var sources: [Source] = []
    var items: [MediaItem] = []
    var projects: [Project] = []
    var tags: [Tag] = []
}

/// Abstraction over the on-disk index so the storage engine can be swapped.
protocol VaultStore {
    func load() throws -> VaultSnapshot
    func save(_ snapshot: VaultSnapshot) throws
}

/// JSON-file implementation of `VaultStore`.
final class JSONVaultStore: VaultStore {
    private let fileURL: URL
    private let queue = DispatchQueue(label: "com.thevault.db", qos: .utility)

    init(filename: String = "VaultIndex.json") {
        let fm = FileManager.default
        let appSupport = (try? fm.url(for: .applicationSupportDirectory,
                                      in: .userDomainMask,
                                      appropriateFor: nil,
                                      create: true)) ?? fm.temporaryDirectory
        let dir = appSupport.appendingPathComponent("The Vault", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        self.fileURL = dir.appendingPathComponent(filename)
    }

    var storageURL: URL { fileURL }

    func load() throws -> VaultSnapshot {
        try queue.sync {
            guard FileManager.default.fileExists(atPath: fileURL.path) else {
                return VaultSnapshot()
            }
            let data = try Data(contentsOf: fileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(VaultSnapshot.self, from: data)
        }
    }

    func save(_ snapshot: VaultSnapshot) throws {
        try queue.sync {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(snapshot)
            try data.write(to: fileURL, options: .atomic)
        }
    }
}
