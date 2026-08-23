//
//  AIContentTagger.swift
//  The Vault
//
//  Stage B of AI logging: an optional, credit-metered pass that enriches a
//  clip's content tags using a vision model. Abstracted behind a protocol so
//  the provider can be swapped; only the Claude implementation is built today
//  (see ClaudeContentTagger).
//

import Foundation

struct AITagResult {
    var contentTags: Set<ContentTag>
    var sceneDescription: String?
    var confidence: Double?
}

enum AITaggerError: Error {
    case invalidKey            // 401 — stop the whole run
    case noKeyframes           // couldn't read frames (drive offline?)
    case api(Int, String)      // other non-200
    case badResponse           // couldn't parse the model output

    var message: String {
        switch self {
        case .invalidKey: return "Invalid Claude API key. Check Settings ▸ Claude API."
        case .noKeyframes: return "Couldn't read frames for a clip."
        case .api(let code, let msg): return "Claude API error \(code): \(msg)"
        case .badResponse: return "Unexpected response from Claude."
        }
    }
}

protocol AIContentTagger {
    /// Model identifier recorded on the analysis (e.g. "claude-haiku-4-5").
    var modelName: String { get }

    /// Classify a clip from a few JPEG keyframes.
    func tag(keyframes: [Data], mediaKind: MediaKind, apiKey: String) async throws -> AITagResult
}
