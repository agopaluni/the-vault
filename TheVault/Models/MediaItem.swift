//
//  MediaItem.swift
//  The Vault
//
//  The fundamental indexed unit: one photo or video file discovered inside a
//  Source. MediaItem is an immutable-ish value record of extracted metadata.
//  Original files are never modified — `url` always points at the on-disk
//  original living inside its source volume.
//

import Foundation
import CoreGraphics

/// Photo vs. video.
enum MediaKind: String, Codable, CaseIterable, Hashable {
    case photo
    case video

    var displayName: String {
        switch self {
        case .photo: return "Photo"
        case .video: return "Video"
        }
    }
}

/// Frame orientation derived from pixel dimensions.
enum Orientation: String, Codable, CaseIterable, Hashable {
    case horizontal   // landscape, wider than tall (e.g. 16:9)
    case vertical     // portrait, taller than wide (e.g. 9:16)
    case square

    var displayName: String {
        switch self {
        case .horizontal: return "Horizontal"
        case .vertical: return "Vertical"
        case .square: return "Square"
        }
    }

    var symbolName: String {
        switch self {
        case .horizontal: return "rectangle"
        case .vertical: return "rectangle.portrait"
        case .square: return "square"
        }
    }

    /// Classify from raw pixel size.
    static func from(width: Int, height: Int) -> Orientation {
        guard width > 0, height > 0 else { return .horizontal }
        let ratio = Double(width) / Double(height)
        if abs(ratio - 1.0) < 0.05 { return .square }
        return ratio > 1.0 ? .horizontal : .vertical
    }
}

/// A single indexed media file plus all extracted metadata.
struct MediaItem: Identifiable, Codable, Hashable {
    let id: UUID

    /// The source this file was discovered in.
    var sourceID: UUID

    /// Absolute path to the original file. Resolved against bookmark data at runtime.
    var path: String

    var filename: String
    var kind: MediaKind

    // Core metadata
    var captureDate: Date?          // EXIF DateTimeOriginal or file creation date
    var fileSize: Int64             // bytes
    var fileFormat: String          // uppercase ext, e.g. "MOV", "HEIC", "RAW"
    var codec: String?              // e.g. "H.264", "HEVC", "ProRes"

    // Image / video dimensions
    var pixelWidth: Int
    var pixelHeight: Int
    var orientation: Orientation

    // Camera
    var cameraMake: String?
    var cameraModel: String?

    // Video-only
    var duration: Double?           // seconds
    var frameRate: Double?          // fps

    // Location
    var latitude: Double?
    var longitude: Double?
    var locationName: String?       // reverse-geocoded "City, Landmark"

    // Organization
    var tagIDs: Set<UUID>
    var projectIDs: Set<UUID>

    // AI-assisted logging (all optional so pre-existing index files still decode).
    // `analysis` holds the suggestion; the user-override fields below win over it.
    var analysis: MediaAnalysis?
    var reviewState: ReviewState?               // nil == unreviewed
    var userContentTags: Set<ContentTag>?       // tags the user added by hand
    var suppressedContentTags: Set<ContentTag>? // AI tags the user removed

    // Bookkeeping
    var indexedAt: Date

    var url: URL { URL(fileURLWithPath: path) }

    var hasLocation: Bool { latitude != nil && longitude != nil }

    /// "Camera source / device" key used for grouping & filtering.
    var cameraLabel: String {
        switch (cameraMake, cameraModel) {
        case let (make?, model?):
            // Avoid "Apple Apple iPhone 15" style duplication.
            if model.localizedCaseInsensitiveContains(make) { return model }
            return "\(make) \(model)"
        case (nil, let model?): return model
        case (let make?, nil): return make
        default: return "Unknown camera"
        }
    }

    var aspectRatio: CGFloat {
        guard pixelHeight > 0 else { return 16.0 / 9.0 }
        return CGFloat(pixelWidth) / CGFloat(pixelHeight)
    }

    init(id: UUID = UUID(),
         sourceID: UUID,
         path: String,
         filename: String,
         kind: MediaKind,
         captureDate: Date? = nil,
         fileSize: Int64 = 0,
         fileFormat: String = "",
         codec: String? = nil,
         pixelWidth: Int = 0,
         pixelHeight: Int = 0,
         orientation: Orientation = .horizontal,
         cameraMake: String? = nil,
         cameraModel: String? = nil,
         duration: Double? = nil,
         frameRate: Double? = nil,
         latitude: Double? = nil,
         longitude: Double? = nil,
         locationName: String? = nil,
         tagIDs: Set<UUID> = [],
         projectIDs: Set<UUID> = [],
         analysis: MediaAnalysis? = nil,
         reviewState: ReviewState? = nil,
         userContentTags: Set<ContentTag>? = nil,
         suppressedContentTags: Set<ContentTag>? = nil,
         indexedAt: Date = Date()) {
        self.id = id
        self.sourceID = sourceID
        self.path = path
        self.filename = filename
        self.kind = kind
        self.captureDate = captureDate
        self.fileSize = fileSize
        self.fileFormat = fileFormat
        self.codec = codec
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.orientation = orientation
        self.cameraMake = cameraMake
        self.cameraModel = cameraModel
        self.duration = duration
        self.frameRate = frameRate
        self.latitude = latitude
        self.longitude = longitude
        self.locationName = locationName
        self.tagIDs = tagIDs
        self.projectIDs = projectIDs
        self.analysis = analysis
        self.reviewState = reviewState
        self.userContentTags = userContentTags
        self.suppressedContentTags = suppressedContentTags
        self.indexedAt = indexedAt
    }

    static func == (lhs: MediaItem, rhs: MediaItem) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

// MARK: - Display helpers

extension MediaItem {
    var formattedFileSize: String {
        ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
    }

    var formattedDuration: String? {
        guard let duration, duration > 0 else { return nil }
        let total = Int(duration.rounded())
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        return String(format: "%d:%02d", m, s)
    }

    var resolutionLabel: String {
        guard pixelWidth > 0, pixelHeight > 0 else { return "—" }
        return "\(pixelWidth) × \(pixelHeight)"
    }
}

// MARK: - AI logging helpers

extension MediaItem {
    /// Fingerprint of the on-disk file, used to skip re-analyzing unchanged media.
    var analysisFingerprint: String { "\(path)|\(fileSize)" }

    /// True if this item still needs an on-device analysis pass.
    var needsAnalysis: Bool {
        guard let analysis else { return true }
        return analysis.fileFingerprint != analysisFingerprint
    }

    var effectiveReviewState: ReviewState { reviewState ?? .unreviewed }

    /// The user's decision always wins over the AI suggestion.
    var effectiveContentTags: Set<ContentTag> {
        var tags = analysis?.contentTags ?? []
        if let suppressed = suppressedContentTags { tags.subtract(suppressed) }
        if let added = userContentTags { tags.formUnion(added) }
        return tags
    }

    var qualityFlags: Set<QualityFlag> { analysis?.flags ?? [] }
    var isDiscarded: Bool { effectiveReviewState == .discarded }
}
