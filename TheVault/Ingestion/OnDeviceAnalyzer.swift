//
//  OnDeviceAnalyzer.swift
//  The Vault
//
//  Stage A of AI logging: a free, on-device pass that flags mistake/quality
//  problems and assigns coarse content tags. Reads sampled frames only (never
//  the whole clip) and reuses the same AVAssetImageGenerator / ImageIO paths
//  as thumbnailing. Nothing here touches the network or the original file
//  beyond reading it.
//
//  Thresholds are deliberately centralized and conservative — they are the
//  first thing to tune against real footage.
//

import Foundation
import AVFoundation
import ImageIO
import Vision
import CoreGraphics
import AppKit

enum OnDeviceAnalyzer {

    // Tunable thresholds (normalized luma 0…1 unless noted).
    private enum T {
        static let statsSide = 96          // downsample for luminance/blur/motion
        static let faceSide: CGFloat = 512 // resolution handed to Vision
        static let maxFrames = 5

        static let shortSeconds = 2.0
        static let accidentalSeconds = 1.0

        // Deliberately conservative — a flag should mean a clear problem, not a
        // maybe. Better to miss than to flag every clip.
        static let darkMean = 0.05
        static let flatVariance = 0.0010
        static let underExposed = 0.07
        static let overExposed = 0.95
        static let clipFraction = 0.65
        static let blurVariance = 0.0004

        static let shake = 0.12
        static let motion = 0.08

        static let faceCoverage = 0.06

        static let audioClip = 0.05
        static let audioSilence = 0.004
        static let dialogueRMS = 0.03
        static let silentRMS = 0.008
        static let windRatio = 0.75
    }

    /// Run the full on-device pass for one item. Returns nil if the file is
    /// unreadable (e.g. drive unmounted).
    static func analyze(_ item: MediaItem, highPrecisionMotion: Bool) -> MediaAnalysis? {
        guard FileManager.default.fileExists(atPath: item.path) else { return nil }
        switch item.kind {
        case .photo: return analyzePhoto(item)
        case .video: return analyzeVideo(item, highPrecision: highPrecisionMotion)
        }
    }

    // MARK: - Photo

    private static func analyzePhoto(_ item: MediaItem) -> MediaAnalysis? {
        guard let large = downsampledCGImage(url: item.url, maxPixel: T.faceSide),
              let gray = grayBuffer(from: large, side: T.statsSide) else { return nil }

        let stats = frameStats(gray, side: T.statsSide)
        let faceCoverage = largestFaceCoverage(in: large)

        var flags: Set<QualityFlag> = []
        var tags: Set<ContentTag> = []

        if stats.mean < T.darkMean && stats.variance < T.flatVariance { flags.insert(.blackOrLensCap) }
        if stats.mean < T.underExposed || stats.mean > T.overExposed || stats.clip > T.clipFraction {
            flags.insert(.poorExposure)
        }
        if stats.blur < T.blurVariance && stats.mean > T.darkMean { flags.insert(.blurry) }

        // Exactly one shot type.
        if faceCoverage > T.faceCoverage { tags.insert(.talkingHead) }
        else { tags.insert(.bRoll) }
        tags.insert(.silent)   // stills have no audio

        let scores = AnalysisScores(luminance: stats.mean, exposureClipping: stats.clip,
                                    blur: stats.blur, faceCoverage: faceCoverage)
        return MediaAnalysis(flags: flags, contentTags: tags, scores: scores,
                             source: .onDevice, fileFingerprint: item.analysisFingerprint)
    }

    // MARK: - Video

    private static func analyzeVideo(_ item: MediaItem, highPrecision: Bool) -> MediaAnalysis? {
        let asset = AVURLAsset(url: item.url)
        let duration = item.duration ?? CMTimeGetSeconds(asset.duration)

        let (largeFrames, grays) = sampleFrames(asset: asset, duration: duration)
        guard !grays.isEmpty else {
            // Couldn't read frames; still flag on duration alone.
            return durationOnlyAnalysis(item, duration: duration)
        }

        // Aggregate per-frame stats.
        var means: [Double] = [], variances: [Double] = [], blurs: [Double] = [], clips: [Double] = []
        for g in grays {
            let s = frameStats(g, side: T.statsSide)
            means.append(s.mean); variances.append(s.variance); blurs.append(s.blur); clips.append(s.clip)
        }
        let meanLuma = means.reduce(0, +) / Double(means.count)
        let meanVar = variances.reduce(0, +) / Double(variances.count)
        let meanBlur = blurs.reduce(0, +) / Double(blurs.count)
        let maxClip = clips.max() ?? 0

        // Motion & shake from consecutive frame differences.
        let (motion, shake) = motionAndShake(grays)
        let faceCoverage = largeFrames.map { largestFaceCoverage(in: $0) }.max() ?? 0
        let audio = AudioAnalyzer.analyze(url: item.url)

        var flags: Set<QualityFlag> = []
        var tags: Set<ContentTag> = []

        if duration < T.accidentalSeconds { flags.insert(.accidentalStart) }
        if duration < T.shortSeconds { flags.insert(.tooShort) }
        if meanLuma < T.darkMean && meanVar < T.flatVariance { flags.insert(.blackOrLensCap) }
        if meanLuma < T.underExposed || meanLuma > T.overExposed || maxClip > T.clipFraction {
            flags.insert(.poorExposure)
        }
        if meanBlur < T.blurVariance && meanLuma > T.darkMean { flags.insert(.blurry) }
        if shake > T.shake { flags.insert(.shaky) }

        // Content tags — exactly one shot type + optional motion + one audio type,
        // so a clip gets ~2–3 meaningful tags rather than all of them.
        if faceCoverage > T.faceCoverage { tags.insert(.talkingHead) } else { tags.insert(.bRoll) }
        if motion > T.motion { tags.insert(.inMotion) }
        // `driving` is intentionally left to the API tier — hard to judge reliably here.

        if let audio {
            if audio.clipFraction > T.audioClip { flags.insert(.audioClipping) }
            if audio.rms < T.audioSilence { flags.insert(.audioSilence) }
            // Wind noise is intentionally NOT auto-flagged on-device: reliably
            // separating low-frequency rumble from ordinary speech/room tone
            // needs real spectral analysis. The score is still recorded, and the
            // AI tier / manual tagging can set it.
            if audio.rms < T.silentRMS { tags.insert(.silent) }
            else if audio.rms > T.dialogueRMS { tags.insert(.dialoguePresent) }
        } else {
            tags.insert(.silent)
        }

        let scores = AnalysisScores(luminance: meanLuma, exposureClipping: maxClip,
                                    blur: meanBlur, shake: shake, motion: motion,
                                    faceCoverage: faceCoverage,
                                    audioPeak: audio?.peak, audioRMS: audio?.rms,
                                    windRatio: audio?.windRatio)
        return MediaAnalysis(flags: flags, contentTags: tags, scores: scores,
                             source: .onDevice, fileFingerprint: item.analysisFingerprint)
    }

    private static func durationOnlyAnalysis(_ item: MediaItem, duration: Double) -> MediaAnalysis {
        var flags: Set<QualityFlag> = []
        if duration < T.accidentalSeconds { flags.insert(.accidentalStart) }
        if duration < T.shortSeconds { flags.insert(.tooShort) }
        return MediaAnalysis(flags: flags, contentTags: [], source: .onDevice,
                             fileFingerprint: item.analysisFingerprint)
    }

    // MARK: - Frame sampling

    /// Returns (larger CGImages for face detection, small gray buffers for stats).
    private static func sampleFrames(asset: AVURLAsset, duration: Double)
        -> (large: [CGImage], gray: [[Float]]) {
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: T.faceSide, height: T.faceSide)
        generator.requestedTimeToleranceBefore = .positiveInfinity
        generator.requestedTimeToleranceAfter = .positiveInfinity

        let fractions: [Double]
        if duration <= 0 || duration.isNaN { fractions = [0] }
        else { fractions = [0.1, 0.3, 0.5, 0.7, 0.9] }

        var large: [CGImage] = []
        var gray: [[Float]] = []
        for f in fractions.prefix(T.maxFrames) {
            let seconds = max(0, duration * f)
            let time = CMTime(seconds: seconds, preferredTimescale: 600)
            guard let cg = try? generator.copyCGImage(at: time, actualTime: nil) else { continue }
            large.append(cg)
            if let g = grayBuffer(from: cg, side: T.statsSide) { gray.append(g) }
        }
        return (large, gray)
    }

    private static func downsampledCGImage(url: URL, maxPixel: CGFloat) -> CGImage? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel
        ]
        return CGImageSourceCreateThumbnailAtIndex(src, 0, options as CFDictionary)
    }

    // MARK: - Pixel statistics

    private struct FrameStats { var mean: Double; var variance: Double; var blur: Double; var clip: Double }

    /// Draw a CGImage into an 8-bit grayscale square and return normalized 0…1 luma.
    private static func grayBuffer(from image: CGImage, side: Int) -> [Float]? {
        let colorSpace = CGColorSpaceCreateDeviceGray()
        var pixels = [UInt8](repeating: 0, count: side * side)
        let ok: Bool = pixels.withUnsafeMutableBytes { raw -> Bool in
            guard let ctx = CGContext(data: raw.baseAddress, width: side, height: side,
                                      bitsPerComponent: 8, bytesPerRow: side,
                                      space: colorSpace,
                                      bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return false }
            ctx.interpolationQuality = .low
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        guard ok else { return nil }
        return pixels.map { Float($0) / 255.0 }
    }

    private static func frameStats(_ buffer: [Float], side: Int) -> FrameStats {
        // Mean, variance, and clipped-pixel fraction.
        var sum = 0.0, sumSq = 0.0, clipped = 0
        for v in buffer {
            let d = Double(v)
            sum += d; sumSq += d * d
            if d < 0.04 || d > 0.96 { clipped += 1 }
        }
        let n = Double(buffer.count)
        let mean = sum / n
        let variance = max(0, sumSq / n - mean * mean)
        let clip = Double(clipped) / n
        let blur = laplacianVariance(buffer, side: side)
        return FrameStats(mean: mean, variance: variance, blur: blur, clip: clip)
    }

    /// Variance of a 3×3 Laplacian response — a standard focus measure.
    private static func laplacianVariance(_ b: [Float], side: Int) -> Double {
        guard side > 2 else { return 0 }
        var sum = 0.0, sumSq = 0.0, count = 0.0
        for y in 1..<(side - 1) {
            for x in 1..<(side - 1) {
                let i = y * side + x
                let lap = 4 * Double(b[i]) - Double(b[i - 1]) - Double(b[i + 1])
                        - Double(b[i - side]) - Double(b[i + side])
                sum += lap; sumSq += lap * lap; count += 1
            }
        }
        guard count > 0 else { return 0 }
        let mean = sum / count
        return max(0, sumSq / count - mean * mean)
    }

    /// Mean inter-frame change (motion) and its variability (shake), 0…~1.
    private static func motionAndShake(_ grays: [[Float]]) -> (motion: Double, shake: Double) {
        guard grays.count > 1 else { return (0, 0) }
        var diffs: [Double] = []
        for i in 1..<grays.count {
            let a = grays[i - 1], b = grays[i]
            guard a.count == b.count else { continue }
            var acc = 0.0
            for j in 0..<a.count { acc += abs(Double(a[j]) - Double(b[j])) }
            diffs.append(acc / Double(a.count))
        }
        guard !diffs.isEmpty else { return (0, 0) }
        let motion = diffs.reduce(0, +) / Double(diffs.count)
        let variance = diffs.reduce(0) { $0 + ($1 - motion) * ($1 - motion) } / Double(diffs.count)
        return (motion, variance.squareRoot())
    }

    // MARK: - Faces

    private static func largestFaceCoverage(in image: CGImage) -> Double {
        let request = VNDetectFaceRectanglesRequest()
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        do { try handler.perform([request]) } catch { return 0 }
        guard let faces = request.results else { return 0 }
        return faces.map { Double($0.boundingBox.width * $0.boundingBox.height) }.max() ?? 0
    }
}
