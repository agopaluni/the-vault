//
//  ThumbnailService.swift
//  The Vault
//
//  Generates and caches thumbnails for media. Photos use ImageIO's thumbnail
//  generation (downsamples without loading the full image); videos extract a
//  frame at the 1-second mark via AVAssetImageGenerator. Results are cached to
//  Library/Caches and kept in a small in-memory NSCache for scroll performance.
//
//  Everything runs off the main thread; callers receive an NSImage via async.
//

import Foundation
import AppKit
import ImageIO
import AVFoundation
import CryptoKit

actor ThumbnailService {
    static let shared = ThumbnailService()

    private let memoryCache = NSCache<NSString, NSImage>()
    private let cacheDir: URL
    private let maxPixel: CGFloat = 480   // long-edge of generated thumbnails
    private let fileManager = FileManager.default

    init() {
        let caches = (try? fileManager.url(for: .cachesDirectory, in: .userDomainMask,
                                           appropriateFor: nil, create: true))
            ?? fileManager.temporaryDirectory
        cacheDir = caches.appendingPathComponent("The Vault/Thumbnails", isDirectory: true)
        try? fileManager.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        memoryCache.countLimit = 500
    }

    /// Returns a thumbnail for the item, generating + caching if necessary.
    /// Returns nil if the file is unreadable (e.g. drive unmounted).
    func thumbnail(for item: MediaItem) async -> NSImage? {
        let key = cacheKey(for: item) as NSString
        if let cached = memoryCache.object(forKey: key) { return cached }

        let diskURL = cacheDir.appendingPathComponent("\(cacheKey(for: item)).jpg")
        if let data = try? Data(contentsOf: diskURL), let image = NSImage(data: data) {
            memoryCache.setObject(image, forKey: key)
            return image
        }

        guard fileManager.fileExists(atPath: item.path) else { return nil }

        let image: NSImage?
        switch item.kind {
        case .photo: image = generatePhotoThumbnail(url: item.url)
        case .video: image = generateVideoThumbnail(url: item.url)
        }

        if let image {
            memoryCache.setObject(image, forKey: key)
            persist(image: image, to: diskURL)
        }
        return image
    }

    /// True if a cached thumbnail already exists (cheap, no generation).
    func hasCachedThumbnail(for item: MediaItem) -> Bool {
        let key = cacheKey(for: item) as NSString
        if memoryCache.object(forKey: key) != nil { return true }
        let diskURL = cacheDir.appendingPathComponent("\(cacheKey(for: item)).jpg")
        return fileManager.fileExists(atPath: diskURL.path)
    }

    // MARK: - Generation

    private func generatePhotoThumbnail(url: URL) -> NSImage? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, options as CFDictionary) else {
            return nil
        }
        return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
    }

    private func generateVideoThumbnail(url: URL) -> NSImage? {
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: maxPixel, height: maxPixel)
        // Frame at the 1-second mark (or start for very short clips).
        let duration = CMTimeGetSeconds(asset.duration)
        let seconds = duration > 1.2 ? 1.0 : max(0, duration / 2)
        let time = CMTime(seconds: seconds, preferredTimescale: 600)
        guard let cg = try? generator.copyCGImage(at: time, actualTime: nil) else { return nil }
        return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
    }

    // MARK: - Caching

    private func persist(image: NSImage, to url: URL) {
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let jpeg = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.8])
        else { return }
        try? jpeg.write(to: url, options: .atomic)
    }

    /// Stable cache key — path + size + mod basis so re-encodes invalidate.
    private func cacheKey(for item: MediaItem) -> String {
        let basis = "\(item.path)|\(item.fileSize)"
        let digest = SHA256.hash(data: Data(basis.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// Clear all cached thumbnails (utility / settings).
    func clearCache() {
        memoryCache.removeAllObjects()
        try? fileManager.removeItem(at: cacheDir)
        try? fileManager.createDirectory(at: cacheDir, withIntermediateDirectories: true)
    }
}
