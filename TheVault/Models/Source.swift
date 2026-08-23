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

    /// The project this source belongs to. `nil` == a global browser source.
    /// Project-owned sources are kept out of the browser's Sources list; all
    /// their media are members of the owning project.
    var ownerProjectID: UUID?

    /// Set at runtime by VolumeMonitor — not persisted.
    var isAvailable: Bool = true

    var indexedItemCount: Int = 0

    var url: URL { URL(fileURLWithPath: path) }

    var isProjectSource: Bool { ownerProjectID != nil }

    enum CodingKeys: String, CodingKey {
        case id, label, path, bookmarkData, mediaType, volumeName, addedAt,
             ownerProjectID, indexedItemCount
    }

    init(id: UUID = UUID(),
         label: String,
         path: String,
         bookmarkData: Data? = nil,
         mediaType: SourceMediaType = .unknown,
         volumeName: String? = nil,
         addedAt: Date = Date(),
         ownerProjectID: UUID? = nil,
         isAvailable: Bool = true,
         indexedItemCount: Int = 0) {
        self.id = id
        self.label = label
        self.path = path
        self.bookmarkData = bookmarkData
        self.mediaType = mediaType
        self.volumeName = volumeName
        self.addedAt = addedAt
        self.ownerProjectID = ownerProjectID
        self.isAvailable = isAvailable
        self.indexedItemCount = indexedItemCount
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
