//
//  MediaAnalysis.swift
//  The Vault
//
//  AI-assisted logging results attached to a clip. These are *suggestions* —
//  stored alongside the item, never applied destructively and always
//  overridable by the user (see MediaItem.userContentTags / reviewState).
//
//  Stage A (on-device, free) fills `flags`, `contentTags`, and `scores`.
//  Stage B (Claude, opt-in) can later enrich `contentTags` and set `apiModel`.
//

import Foundation

/// A likely problem with a clip — mistake footage or a technical quality issue.
enum QualityFlag: String, Codable, CaseIterable, Hashable {
    case tooShort           // under ~2s
    case accidentalStart    // sub-second / likely a fat-finger record
    case blackOrLensCap     // black frame / lens cap / no image
    case blurry             // low edge energy
    case shaky              // high inter-frame jitter
    case poorExposure       // badly under- or over-exposed
    case audioClipping      // digital clipping on the audio track
    case audioSilence       // effectively silent
    case windNoise          // low-frequency rumble dominates the audio

    var isMistake: Bool {
        switch self {
        case .tooShort, .accidentalStart, .blackOrLensCap: return true
        default: return false
        }
    }

    var displayName: String {
        switch self {
        case .tooShort: return "Too short"
        case .accidentalStart: return "Accidental start"
        case .blackOrLensCap: return "Black / lens cap"
        case .blurry: return "Blurry"
        case .shaky: return "Shaky"
        case .poorExposure: return "Poor exposure"
        case .audioClipping: return "Audio clipping"
        case .audioSilence: return "Silent"
        case .windNoise: return "Wind noise"
        }
    }

    var symbolName: String {
        switch self {
        case .tooShort: return "timer"
        case .accidentalStart: return "hand.raised"
        case .blackOrLensCap: return "circle.slash"
        case .blurry: return "camera.filters"
        case .shaky: return "waveform.path.ecg"
        case .poorExposure: return "sun.max.trianglebadge.exclamationmark"
        case .audioClipping: return "waveform.badge.exclamationmark"
        case .audioSilence: return "speaker.slash"
        case .windNoise: return "wind"
        }
    }
}

/// What kind of shot this clip is — used for grouping/filtering the project
/// view and for manual tagging. A handful are auto-detected on-device; the rest
/// are available for the user to apply by hand (or via the Claude tier).
enum ContentTag: String, Codable, CaseIterable, Hashable {
    // Subject / framing
    case talkingHead        // a face on camera
    case interview
    case closeUp
    case wideShot
    case landscape
    case bRoll              // establishing / no subject
    case establishing
    // Motion
    case inMotion           // handheld or moving camera
    case action
    case driving
    // Audio
    case dialoguePresent    // "Speaking"
    case silent
    case music

    var displayName: String {
        switch self {
        case .talkingHead: return "Talking Head"
        case .interview: return "Interview"
        case .closeUp: return "Close-Up"
        case .wideShot: return "Wide Shot"
        case .landscape: return "Landscape"
        case .bRoll: return "B-Roll"
        case .establishing: return "Establishing"
        case .inMotion: return "In Motion"
        case .action: return "Action"
        case .driving: return "Driving"
        case .dialoguePresent: return "Speaking"
        case .silent: return "Silent"
        case .music: return "Music"
        }
    }

    var symbolName: String {
        switch self {
        case .talkingHead: return "person.crop.square"
        case .interview: return "person.2"
        case .closeUp: return "camera.macro"
        case .wideShot: return "rectangle.expand.vertical"
        case .landscape: return "mountain.2"
        case .bRoll: return "photo"
        case .establishing: return "building.2"
        case .inMotion: return "figure.walk.motion"
        case .action: return "bolt"
        case .driving: return "car"
        case .dialoguePresent: return "text.bubble"
        case .silent: return "speaker.slash"
        case .music: return "music.note"
        }
    }

    /// Grouping for the manual tag editor.
    enum Group: String, CaseIterable { case subject = "Subject", motion = "Motion", audio = "Audio" }
    var group: Group {
        switch self {
        case .talkingHead, .interview, .closeUp, .wideShot, .landscape, .bRoll, .establishing: return .subject
        case .inMotion, .action, .driving: return .motion
        case .dialoguePresent, .silent, .music: return .audio
        }
    }
}

/// The user's decision about a clip. Overrides the AI's suggestion; never
/// deletes the original file.
enum ReviewState: String, Codable, Hashable {
    case unreviewed
    case approved
    case discarded
}

/// Which tier produced an analysis.
enum AnalysisSource: String, Codable, Hashable {
    case onDevice
    case api
    case hybrid
}

/// Raw measurements kept for threshold tuning and UI ("why was this flagged").
struct AnalysisScores: Codable, Hashable {
    var luminance: Double?          // mean, 0…1
    var exposureClipping: Double?   // fraction of clipped pixels, 0…1
    var blur: Double?               // Laplacian variance (higher = sharper)
    var shake: Double?              // inter-frame jitter, 0…1
    var motion: Double?             // mean inter-frame change, 0…1
    var faceCoverage: Double?       // largest face area / frame, 0…1
    var audioPeak: Double?          // 0…1
    var audioRMS: Double?           // 0…1
    var windRatio: Double?          // low-frequency dominance, 0…1
}

struct MediaAnalysis: Codable, Hashable {
    var flags: Set<QualityFlag>
    var contentTags: Set<ContentTag>
    var scores: AnalysisScores?
    var source: AnalysisSource
    var apiModel: String?           // e.g. "claude-haiku-4-5" once Stage B runs
    var sceneDescription: String?   // short description from the Claude tier
    var analyzedAt: Date

    /// Content hash of the analyzed file (path + size) so we never re-analyze
    /// unchanged media. Mirrors the thumbnail cache key strategy.
    var fileFingerprint: String

    init(flags: Set<QualityFlag> = [],
         contentTags: Set<ContentTag> = [],
         scores: AnalysisScores? = nil,
         source: AnalysisSource = .onDevice,
         apiModel: String? = nil,
         sceneDescription: String? = nil,
         analyzedAt: Date = Date(),
         fileFingerprint: String) {
        self.flags = flags
        self.contentTags = contentTags
        self.scores = scores
        self.source = source
        self.apiModel = apiModel
        self.sceneDescription = sceneDescription
        self.analyzedAt = analyzedAt
        self.fileFingerprint = fileFingerprint
    }

    var hasMistakeFlag: Bool { flags.contains { $0.isMistake } }
    var hasQualityIssue: Bool { !flags.isEmpty }
}
