//
//  Source.swift
//  The Vault
//
//  A "source folder" the user has added — a directory on any mounted volume
//  (internal disk, SD card, SSD, external drive). The Vault indexes media
//  inside a source but NEVER moves, modifies, or deletes the originals.
//

import Foundation

/// Best-effort classification of the kind of volume a source lives on,
/// used purely for the origin label / icon.
enum SourceMediaType: String, Codable, CaseIterable {
    case internalDrive
    case sdCard
    case ssd
    case externalDrive
    case unknown

    var defaultLabel: String {
        switch self {
        case .internalDrive: return "Internal Drive"
        case .sdCard: return "SD Card"
        case .ssd: return "SSD"
        case .externalDrive: return "External Drive"
        case .unknown: return "Folder"
        }
    }

    var symbolName: String {
        switch self {
        case .internalDrive: return "internaldrive"
        case .sdCard: return "sdcard"
        case .ssd: return "externaldrive.connected.to.line.below"
        case .externalDrive: return "externaldrive"
        case .unknown: return "folder"
        }
    }
}

struct Source: Identifiable, Codable, Hashable {
    let id: UUID

    /// User-facing origin label, e.g. "A7IV - SD Card", "iPhone - SSD".
    var label: String

    /// Absolute path of the source folder at the time it was added.
    var path: String

    /// Security-scoped bookmark so we can re-resolve access across launches.
    var bookmarkData: Data?

    var mediaType: SourceMediaType

    /// Volume name the folder lived on, used for hot-plug detection.
    var volumeName: String?

    var addedAt: Date

    /// Projects this source is attached to. A single folder is indexed ONCE and
    /// can serve any number of projects — attaching it elsewhere never
    /// re-indexes its files.
    var projectIDs: Set<UUID>

    /// Whether this source appears in the browser's Sources list. A source can
    /// be both global and attached to projects; the flag only controls browser
    /// visibility, so project footage doesn't clutter "All Media".
    var isGlobal: Bool

    /// Set at runtime by VolumeMonitor — not persisted.
    var isAvailable: Bool = true

    var indexedItemCount: Int = 0

    var url: URL { URL(fileURLWithPath: path) }

    /// Standardized path — the identity of a source folder.
    var canonicalPath: String { url.standardizedFileURL.path }

    var isProjectSource: Bool { !projectIDs.isEmpty }

    /// No longer referenced by the browser or any project.
    var isOrphaned: Bool { !isGlobal && projectIDs.isEmpty }

    enum CodingKeys: String, CodingKey {
        case id, label, path, bookmarkData, mediaType, volumeName, addedAt,
             projectIDs, isGlobal, indexedItemCount
        // Legacy (pre-v4): a source belonged to at most one project.
        case ownerProjectID
    }

    init(id: UUID = UUID(),
         label: String,
         path: String,
         bookmarkData: Data? = nil,
         mediaType: SourceMediaType = .unknown,
         volumeName: String? = nil,
         addedAt: Date = Date(),
         projectIDs: Set<UUID> = [],
         isGlobal: Bool = true,
         isAvailable: Bool = true,
         indexedItemCount: Int = 0) {
        self.id = id
        self.label = label
        self.path = path
        self.bookmarkData = bookmarkData
        self.mediaType = mediaType
        self.volumeName = volumeName
        self.addedAt = addedAt
        self.projectIDs = projectIDs
        self.isGlobal = isGlobal
        self.isAvailable = isAvailable
        self.indexedItemCount = indexedItemCount
    }

    /// Custom decode so pre-v4 indexes (single `ownerProjectID`) still load.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        label = try c.decode(String.self, forKey: .label)
        path = try c.decode(String.self, forKey: .path)
        bookmarkData = try c.decodeIfPresent(Data.self, forKey: .bookmarkData)
        mediaType = try c.decodeIfPresent(SourceMediaType.self, forKey: .mediaType) ?? .unknown
        volumeName = try c.decodeIfPresent(String.self, forKey: .volumeName)
        addedAt = try c.decodeIfPresent(Date.self, forKey: .addedAt) ?? Date()
        indexedItemCount = try c.decodeIfPresent(Int.self, forKey: .indexedItemCount) ?? 0
        isAvailable = true

        if let ids = try c.decodeIfPresent(Set<UUID>.self, forKey: .projectIDs) {
            projectIDs = ids
            isGlobal = try c.decodeIfPresent(Bool.self, forKey: .isGlobal) ?? ids.isEmpty
        } else if let legacyOwner = try c.decodeIfPresent(UUID.self, forKey: .ownerProjectID) {
            projectIDs = [legacyOwner]     // was a project-owned source
            isGlobal = false
        } else {
            projectIDs = []                // was a browser source
            isGlobal = true
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(label, forKey: .label)
        try c.encode(path, forKey: .path)
        try c.encodeIfPresent(bookmarkData, forKey: .bookmarkData)
        try c.encode(mediaType, forKey: .mediaType)
        try c.encodeIfPresent(volumeName, forKey: .volumeName)
        try c.encode(addedAt, forKey: .addedAt)
        try c.encode(projectIDs, forKey: .projectIDs)
        try c.encode(isGlobal, forKey: .isGlobal)
        try c.encode(indexedItemCount, forKey: .indexedItemCount)
    }

    static func == (lhs: Source, rhs: Source) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

extension Source {
    /// Heuristic to guess the media type from the volume's mount path.
    static func guessMediaType(for url: URL) -> SourceMediaType {
        let path = url.path
        if path.hasPrefix("/Volumes/") {
            let lower = path.lowercased()
            if lower.contains("sd") || lower.contains("card") { return .sdCard }
            if lower.contains("ssd") { return .ssd }
            return .externalDrive
        }
        return .internalDrive
    }

    static func volumeName(for url: URL) -> String? {
        let values = try? url.resourceValues(forKeys: [.volumeNameKey])
        return values?.volumeName
    }
}
