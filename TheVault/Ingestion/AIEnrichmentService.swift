//
//  AIEnrichmentService.swift
//  The Vault
//
//  Runs Stage B (Claude content tagging) over a set of clips. Extracts a few
//  downsampled JPEG keyframes per clip and calls the tagger with bounded
//  concurrency (fast, but polite to rate limits). Results stream back to the
//  delegate; an invalid key stops the whole run immediately.
//
//  Cost control lives in the caller (LibraryStore) which gates out mistake and
//  already-enriched clips before handing work here.
//

import Foundation
import AVFoundation
import ImageIO
import AppKit

protocol AIEnrichmentDelegate: AnyObject {
    func enrichment(_ service: AIEnrichmentService, didEnrich itemID: UUID,
                    tags: Set<ContentTag>, scene: String?, model: String)
    func enrichment(_ service: AIEnrichmentService, didProgress fraction: Double, status: String)
    func enrichment(_ service: AIEnrichmentService, didFail message: String)
    func enrichmentDidFinish(_ service: AIEnrichmentService)
}

final class AIEnrichmentService {
    weak var delegate: AIEnrichmentDelegate?

    private let tagger: AIContentTagger
    private let maxConcurrent = 4

    init(tagger: AIContentTagger = ClaudeContentTagger()) {
        self.tagger = tagger
    }

    func enrich(items: [MediaItem], apiKey: String) {
        guard !items.isEmpty else { delegate?.enrichmentDidFinish(self); return }
        Task.detached(priority: .userInitiated) { [weak self] in
            await self?.run(items: items, apiKey: apiKey)
        }
    }

    private func run(items: [MediaItem], apiKey: String) async {
        let total = items.count
        var completed = 0
        var index = 0
        var authFailed = false

        while index < items.count && !authFailed {
            let end = min(index + maxConcurrent, items.count)
            let chunk = Array(items[index..<end])
            index = end

            let results = await withTaskGroup(
                of: (UUID, Result<AITagResult, AITaggerError>).self
            ) { group -> [(UUID, Result<AITagResult, AITaggerError>)] in
                for item in chunk {
                    group.addTask { [tagger] in
                        let frames = Keyframes.jpeg(for: item)
                        guard !frames.isEmpty else { return (item.id, .failure(.noKeyframes)) }
                        do {
                            let result = try await tagger.tag(keyframes: frames,
                                                              mediaKind: item.kind, apiKey: apiKey)
                            return (item.id, .success(result))
                        } catch let error as AITaggerError {
                            return (item.id, .failure(error))
                        } catch {
                            return (item.id, .failure(.badResponse))
                        }
                    }
                }
                var acc: [(UUID, Result<AITagResult, AITaggerError>)] = []
                for await r in group { acc.append(r) }
                return acc
            }

            for (id, result) in results {
                switch result {
                case .success(let tagResult):
                    delegate?.enrichment(self, didEnrich: id, tags: tagResult.contentTags,
                                         scene: tagResult.sceneDescription, model: tagger.modelName)
                case .failure(.invalidKey):
                    authFailed = true
                case .failure:
                    break   // skip this clip, keep going
                }
                completed += 1
                delegate?.enrichment(self, didProgress: Double(completed) / Double(total),
                                     status: "Enhancing with AI — \(completed)/\(total)")
            }
        }

        if authFailed {
            delegate?.enrichment(self, didFail: AITaggerError.invalidKey.message)
        }
        delegate?.enrichmentDidFinish(self)
    }
}

// MARK: - Keyframe extraction

enum Keyframes {
    /// Up to `max` downsampled JPEG keyframes for a clip, sized for a vision API.
    static func jpeg(for item: MediaItem, max count: Int = 3, maxPixel: CGFloat = 512) -> [Data] {
        guard FileManager.default.fileExists(atPath: item.path) else { return [] }
        let images: [CGImage]
        switch item.kind {
        case .photo:
            images = photoImage(url: item.url, maxPixel: maxPixel).map { [$0] } ?? []
        case .video:
            images = videoFrames(url: item.url, duration: item.duration, count: count, maxPixel: maxPixel)
        }
        return images.compactMap(jpegData)
    }

    private static func photoImage(url: URL, maxPixel: CGFloat) -> CGImage? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel
        ]
        return CGImageSourceCreateThumbnailAtIndex(src, 0, options as CFDictionary)
    }

    private static func videoFrames(url: URL, duration: Double?, count: Int, maxPixel: CGFloat) -> [CGImage] {
        let asset = AVURLAsset(url: url)
        let total = duration ?? CMTimeGetSeconds(asset.duration)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: maxPixel, height: maxPixel)
        generator.requestedTimeToleranceBefore = .positiveInfinity
        generator.requestedTimeToleranceAfter = .positiveInfinity

        let fractions = total > 0 ? [0.25, 0.5, 0.75] : [0.0]
        var frames: [CGImage] = []
        for f in fractions.prefix(count) {
            let time = CMTime(seconds: max(0, total * f), preferredTimescale: 600)
            if let cg = try? generator.copyCGImage(at: time, actualTime: nil) { frames.append(cg) }
        }
        return frames
    }

    private static func jpegData(_ image: CGImage) -> Data? {
        let rep = NSBitmapImageRep(cgImage: image)
        return rep.representation(using: .jpeg, properties: [.compressionFactor: 0.7])
    }
}
