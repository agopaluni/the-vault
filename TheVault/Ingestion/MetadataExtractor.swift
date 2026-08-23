//
//  MetadataExtractor.swift
//  The Vault
//
//  Reads metadata from a single file without copying or modifying it.
//  Photos go through ImageIO (CGImageSource) for EXIF/GPS/TIFF; videos go
//  through AVFoundation for duration, dimensions, frame rate, and codec.
//

import Foundation
import ImageIO
import AVFoundation
import CoreServices
import UniformTypeIdentifiers

enum MetadataExtractor {

    /// Known photo & video file extensions (lowercased, no dot).
    static let photoExtensions: Set<String> = [
        "jpg", "jpeg", "png", "heic", "heif", "tiff", "tif", "gif", "bmp",
        "raw", "arw", "cr2", "cr3", "nef", "dng", "raf", "rw2", "orf", "webp"
    ]
    static let videoExtensions: Set<String> = [
        "mov", "mp4", "m4v", "avi", "mkv", "mts", "m2ts", "mpg", "mpeg",
        "wmv", "flv", "webm", "3gp", "hevc"
    ]

    static func kind(for url: URL) -> MediaKind? {
        let ext = url.pathExtension.lowercased()
        if photoExtensions.contains(ext) { return .photo }
        if videoExtensions.contains(ext) { return .video }
        return nil
    }

    /// Extract a full MediaItem (minus location name, which is geocoded later).
    static func extract(url: URL, sourceID: UUID) -> MediaItem? {
        guard let kind = kind(for: url) else { return nil }
        let fileSize = fileSize(of: url)
        let format = url.pathExtension.uppercased()

        switch kind {
        case .photo:
            return extractPhoto(url: url, sourceID: sourceID, fileSize: fileSize, format: format)
        case .video:
            return extractVideo(url: url, sourceID: sourceID, fileSize: fileSize, format: format)
        }
    }

    // MARK: - Photo

    private static func extractPhoto(url: URL, sourceID: UUID,
                                     fileSize: Int64, format: String) -> MediaItem {
        var item = MediaItem(sourceID: sourceID, path: url.path,
                             filename: url.lastPathComponent, kind: .photo,
                             fileSize: fileSize, fileFormat: format)
        item.captureDate = fileCreationDate(url)   // fallback

        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any]
        else { return item }

        if let w = props[kCGImagePropertyPixelWidth] as? Int { item.pixelWidth = w }
        if let h = props[kCGImagePropertyPixelHeight] as? Int { item.pixelHeight = h }
        item.orientation = Orientation.from(width: item.pixelWidth, height: item.pixelHeight)

        // TIFF: camera make/model
        if let tiff = props[kCGImagePropertyTIFFDictionary] as? [CFString: Any] {
            item.cameraMake = tiff[kCGImagePropertyTIFFMake] as? String
            item.cameraModel = tiff[kCGImagePropertyTIFFModel] as? String
        }

        // EXIF: capture date
        if let exif = props[kCGImagePropertyExifDictionary] as? [CFString: Any] {
            if let raw = exif[kCGImagePropertyExifDateTimeOriginal] as? String,
               let date = exifDateFormatter.date(from: raw) {
                item.captureDate = date
            }
        }

        // GPS
        if let gps = props[kCGImagePropertyGPSDictionary] as? [CFString: Any] {
            item.latitude = signedCoordinate(gps[kCGImagePropertyGPSLatitude],
                                             ref: gps[kCGImagePropertyGPSLatitudeRef], negativeRef: "S")
            item.longitude = signedCoordinate(gps[kCGImagePropertyGPSLongitude],
                                              ref: gps[kCGImagePropertyGPSLongitudeRef], negativeRef: "W")
        }

        item.codec = format   // for stills, format is the most meaningful "codec"
        return item
    }

    private static func signedCoordinate(_ value: Any?, ref: Any?, negativeRef: String) -> Double? {
        guard let degrees = value as? Double else { return nil }
        if let r = ref as? String, r.uppercased() == negativeRef { return -degrees }
        return degrees
    }

    // MARK: - Video

    private static func extractVideo(url: URL, sourceID: UUID,
                                     fileSize: Int64, format: String) -> MediaItem {
        var item = MediaItem(sourceID: sourceID, path: url.path,
                             filename: url.lastPathComponent, kind: .video,
                             fileSize: fileSize, fileFormat: format)
        item.captureDate = fileCreationDate(url)

        let asset = AVURLAsset(url: url)
        item.duration = CMTimeGetSeconds(asset.duration)
        if item.duration?.isNaN == true { item.duration = nil }

        // Creation date from asset metadata, if present.
        if let creationItem = asset.creationDate,
           let date = creationItem.dateValue {
            item.captureDate = date
        }

        if let track = asset.tracks(withMediaType: .video).first {
            let size = track.naturalSize.applying(track.preferredTransform)
            item.pixelWidth = Int(abs(size.width))
            item.pixelHeight = Int(abs(size.height))
            item.orientation = Orientation.from(width: item.pixelWidth, height: item.pixelHeight)
            item.frameRate = Double(track.nominalFrameRate)
            item.codec = codecName(for: track)
        }

        // GPS via ISO6709 common metadata (e.g. "+34.0522-118.2437/").
        for meta in asset.commonMetadata where meta.commonKey == .commonKeyLocation {
            if let iso = meta.stringValue, let coord = parseISO6709(iso) {
                item.latitude = coord.lat
                item.longitude = coord.lon
            }
        }

        // Camera make/model from QuickTime metadata if available.
        let qt = asset.metadata(forFormat: .quickTimeMetadata)
        for meta in qt {
            guard let key = meta.key as? String else { continue }
            if key.contains("make"), item.cameraMake == nil { item.cameraMake = meta.stringValue }
            if key.contains("model"), item.cameraModel == nil { item.cameraModel = meta.stringValue }
        }

        return item
    }

    private static func codecName(for track: AVAssetTrack) -> String? {
        guard let desc = track.formatDescriptions.first else { return nil }
        // swiftlint:disable:next force_cast
        let cmDesc = desc as! CMFormatDescription
        let code = CMFormatDescriptionGetMediaSubType(cmDesc)
        return fourCCString(code)
    }

    private static func fourCCString(_ code: FourCharCode) -> String {
        let bytes: [CChar] = [
            CChar((code >> 24) & 0xFF), CChar((code >> 16) & 0xFF),
            CChar((code >> 8) & 0xFF), CChar(code & 0xFF), 0
        ]
        let raw = String(cString: bytes).trimmingCharacters(in: .whitespaces)
        // Map common codes to friendly names.
        switch raw.lowercased() {
        case "avc1", "h264": return "H.264"
        case "hvc1", "hev1": return "HEVC"
        case "apcn", "apch", "apcs", "apco", "ap4h": return "ProRes"
        case "mp4v": return "MPEG-4"
        default: return raw.isEmpty ? "Unknown" : raw.uppercased()
        }
    }

    /// Parse ISO 6709 location string into signed lat/lon.
    private static func parseISO6709(_ s: String) -> (lat: Double, lon: Double)? {
        // Matches leading-sign groups: e.g. +34.0522-118.2437+010.0/
        let pattern = "([+-]\\d+\\.?\\d*)([+-]\\d+\\.?\\d*)"
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)),
              match.numberOfRanges >= 3,
              let latR = Range(match.range(at: 1), in: s),
              let lonR = Range(match.range(at: 2), in: s),
              let lat = Double(s[latR]), let lon = Double(s[lonR])
        else { return nil }
        return (lat, lon)
    }

    // MARK: - File attributes

    static func fileSize(of url: URL) -> Int64 {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey, .totalFileAllocatedSizeKey])
        return Int64(values?.fileSize ?? 0)
    }

    static func fileCreationDate(_ url: URL) -> Date? {
        let values = try? url.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey])
        return values?.creationDate ?? values?.contentModificationDate
    }

    /// EXIF dates look like "2024:06:21 14:33:01".
    static let exifDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy:MM:dd HH:mm:ss"
        f.timeZone = TimeZone.current
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()
}
