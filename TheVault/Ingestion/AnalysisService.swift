//
//  AnalysisService.swift
//  The Vault
//
//  Background queue that runs the on-device analysis pass over a set of items
//  and streams results back to the delegate (LibraryStore) — the same shape as
//  IngestionService. Runs serially on a utility queue to stay responsive and
//  cool on large libraries; results are cached on the item, so this never
//  re-runs for unchanged media.
//

import Foundation

protocol AnalysisServiceDelegate: AnyObject {
    func analysis(_ service: AnalysisService, didAnalyze itemID: UUID, result: MediaAnalysis)
    func analysis(_ service: AnalysisService, didProgress fraction: Double, status: String)
    func analysisDidFinish(_ service: AnalysisService)
}

final class AnalysisService {
    weak var delegate: AnalysisServiceDelegate?

    private let queue = DispatchQueue(label: "com.thevault.analysis", qos: .utility)
    private var cancelled = false

    /// Analyze the given items. Only items that still need analysis should be
    /// passed in (the caller filters on `MediaItem.needsAnalysis`).
    func analyze(items: [MediaItem], highPrecisionMotion: Bool) {
        guard !items.isEmpty else { delegate?.analysisDidFinish(self); return }
        cancelled = false
        queue.async { [weak self] in
            guard let self else { return }
            let total = items.count
            for (index, item) in items.enumerated() {
                if self.cancelled { break }
                if let result = OnDeviceAnalyzer.analyze(item, highPrecisionMotion: highPrecisionMotion) {
                    self.delegate?.analysis(self, didAnalyze: item.id, result: result)
                }
                let fraction = Double(index + 1) / Double(total)
                self.delegate?.analysis(self, didProgress: fraction,
                                        status: "Analyzing footage — \(index + 1)/\(total)")
            }
            self.delegate?.analysisDidFinish(self)
        }
    }

    func cancelAll() { cancelled = true }
}
