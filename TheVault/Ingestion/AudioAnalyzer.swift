//
//  AudioAnalyzer.swift
//  The Vault
//
//  Decodes a short window of a clip's audio track (read-only) and derives
//  cheap metrics with Accelerate/vDSP: peak level (clipping), RMS (silence /
//  dialogue presence), and a low-frequency dominance ratio (wind rumble).
//
//  No FFT: wind is approximated by comparing full-signal energy to the energy
//  remaining after a first-difference high-pass — low-frequency content
//  collapses under the high-pass, so a low residual ⇒ rumble-dominated.
//

import Foundation
import AVFoundation
import Accelerate

struct AudioMetrics {
    var peak: Double          // 0…1, max absolute sample
    var rms: Double           // 0…1
    var clipFraction: Double  // fraction of samples at/near full scale
    var windRatio: Double     // 0…1, higher ⇒ more low-frequency dominance
}

enum AudioAnalyzer {
    /// Analyze up to `maxSeconds` of mono audio. Returns nil if there is no
    /// audio track or the track can't be read.
    static func analyze(url: URL, maxSeconds: Double = 20) -> AudioMetrics? {
        let asset = AVURLAsset(url: url)
        guard let track = asset.tracks(withMediaType: .audio).first else { return nil }

        let sampleRate = 22_050.0
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
            AVNumberOfChannelsKey: 1,
            AVSampleRateKey: sampleRate
        ]

        guard let reader = try? AVAssetReader(asset: asset) else { return nil }
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: settings)
        guard reader.canAdd(output) else { return nil }
        reader.add(output)
        guard reader.startReading() else { return nil }

        var samples: [Float] = []
        let maxSamples = Int(sampleRate * maxSeconds)
        samples.reserveCapacity(min(maxSamples, 1 << 20))

        while samples.count < maxSamples,
              let buffer = output.copyNextSampleBuffer() {
            guard let block = CMSampleBufferGetDataBuffer(buffer) else { continue }
            var lengthAtOffset = 0
            var totalLength = 0
            var dataPointer: UnsafeMutablePointer<Int8>?
            let status = CMBlockBufferGetDataPointer(block, atOffset: 0,
                                                     lengthAtOffsetOut: &lengthAtOffset,
                                                     totalLengthOut: &totalLength,
                                                     dataPointerOut: &dataPointer)
            if status == kCMBlockBufferNoErr, let dataPointer {
                let count = totalLength / MemoryLayout<Float>.size
                dataPointer.withMemoryRebound(to: Float.self, capacity: count) { ptr in
                    samples.append(contentsOf: UnsafeBufferPointer(start: ptr, count: count))
                }
            }
            CMSampleBufferInvalidate(buffer)
        }
        reader.cancelReading()

        guard samples.count > 32 else { return nil }
        return metrics(from: samples)
    }

    private static func metrics(from samples: [Float]) -> AudioMetrics {
        let n = vDSP_Length(samples.count)

        // Peak (max magnitude) and RMS via vDSP.
        var peak: Float = 0
        vDSP_maxmgv(samples, 1, &peak, n)
        var rms: Float = 0
        vDSP_rmsqv(samples, 1, &rms, n)

        // Clip fraction: samples within ~0.5 dB of full scale.
        let clipThreshold: Float = 0.98
        var clipCount = 0
        for s in samples where abs(s) >= clipThreshold { clipCount += 1 }
        let clipFraction = Double(clipCount) / Double(samples.count)

        // First-difference high-pass; compare residual RMS to full RMS.
        var diff = [Float](repeating: 0, count: samples.count - 1)
        samples.withUnsafeBufferPointer { src in
            for i in 0..<(samples.count - 1) {
                diff[i] = src[i + 1] - src[i]
            }
        }
        var diffRMS: Float = 0
        vDSP_rmsqv(diff, 1, &diffRMS, vDSP_Length(diff.count))

        // windRatio: how much energy the high-pass removed (low-freq share).
        let windRatio: Double
        if rms > 1e-6 {
            let residual = Double(diffRMS) / Double(rms)   // ~0 = all low-freq, ~2 = broadband
            windRatio = max(0, min(1, 1 - residual / 1.4))
        } else {
            windRatio = 0
        }

        return AudioMetrics(peak: Double(peak),
                            rms: Double(rms),
                            clipFraction: clipFraction,
                            windRatio: windRatio)
    }
}
