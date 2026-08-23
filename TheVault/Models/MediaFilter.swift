//
//  MediaFilter.swift
//  The Vault
//
//  The active filter + sort criteria applied to the browser. Pure value type
//  so it can be diffed and described in the status bar.
//

import Foundation

enum SortKey: String, CaseIterable, Identifiable {
    case date = "Date"
    case fileSize = "File Size"
    case duration = "Duration"
    case camera = "Camera"
    case location = "Location"

    var id: String { rawValue }
}

enum SortDirection {
    case ascending, descending
    var toggled: SortDirection { self == .ascending ? .descending : .ascending }
    var symbolName: String { self == .ascending ? "arrow.up" : "arrow.down" }
}

/// Tri-state media-type filter.
enum MediaTypeFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case photos = "Photos"
    case videos = "Videos"
    var id: String { rawValue }
}

enum TagFilter: String, CaseIterable, Identifiable {
    case any = "Any"
    case tagged = "Tagged"
    case untagged = "Untagged"
    var id: String { rawValue }
}

/// Filter by AI quality-flag state.
enum FlagFilter: String, CaseIterable, Identifiable {
    case any = "Any"
    case flagged = "Flagged"      // any quality flag
    case mistakes = "Mistakes"    // likely-mistake flag
    case clean = "Clean"          // no flags
    var id: String { rawValue }
}

/// Filter by whether/how a clip was analyzed.
enum AnalysisFilter: String, CaseIterable, Identifiable {
    case any = "Any"
    case analyzed = "Analyzed"
    case notAnalyzed = "Not Analyzed"
    case aiEnriched = "AI-Enriched"   // the Claude tier has run
    var id: String { rawValue }
}

struct MediaFilter {
    var mediaType: MediaTypeFilter = .all
    var orientations: Set<Orientation> = []          // empty = all
    var cameraLabels: Set<String> = []               // empty = all
    var fileFormats: Set<String> = []                // empty = all (uppercase ext)
    var sourceIDs: Set<UUID> = []                    // empty = all sources
    var dateRange: ClosedRange<Date>? = nil
    var locationQuery: String = ""
    var tagFilter: TagFilter = .any
    var tagIDs: Set<UUID> = []                        // require ANY of these tags
    var projectID: UUID? = nil                       // restrict to one project's members

    // AI logging filters
    var contentTags: Set<ContentTag> = []            // require ANY of these content tags
    var flagFilter: FlagFilter = .any
    var analysisFilter: AnalysisFilter = .any
    var showDiscarded: Bool = false                  // hide discarded clips by default

    var sortKey: SortKey = .date
    var sortDirection: SortDirection = .descending

    /// True when no narrowing criteria are active (used to short-circuit work).
    var isEmpty: Bool {
        mediaType == .all &&
        orientations.isEmpty &&
        cameraLabels.isEmpty &&
        fileFormats.isEmpty &&
        sourceIDs.isEmpty &&
        dateRange == nil &&
        locationQuery.trimmingCharacters(in: .whitespaces).isEmpty &&
        tagFilter == .any &&
        tagIDs.isEmpty &&
        projectID == nil &&
        contentTags.isEmpty &&
        flagFilter == .any &&
        analysisFilter == .any
    }

    var activeCriteriaCount: Int {
        var n = 0
        if mediaType != .all { n += 1 }
        if !orientations.isEmpty { n += 1 }
        if !cameraLabels.isEmpty { n += 1 }
        if !fileFormats.isEmpty { n += 1 }
        if !sourceIDs.isEmpty { n += 1 }
        if dateRange != nil { n += 1 }
        if !locationQuery.trimmingCharacters(in: .whitespaces).isEmpty { n += 1 }
        if tagFilter != .any { n += 1 }
        if !tagIDs.isEmpty { n += 1 }
        if projectID != nil { n += 1 }
        if !contentTags.isEmpty { n += 1 }
        if flagFilter != .any { n += 1 }
        if analysisFilter != .any { n += 1 }
        return n
    }

    mutating func reset() {
        self = MediaFilter(sortKey: sortKey, sortDirection: sortDirection)
    }
}

// MARK: - Matching & sorting

extension MediaFilter {
    /// Returns true if `item` passes every active criterion.
    func matches(_ item: MediaItem) -> Bool {
        switch mediaType {
        case .all: break
        case .photos: if item.kind != .photo { return false }
        case .videos: if item.kind != .video { return false }
        }

        if !orientations.isEmpty, !orientations.contains(item.orientation) { return false }
        if !cameraLabels.isEmpty, !cameraLabels.contains(item.cameraLabel) { return false }
        if !fileFormats.isEmpty, !fileFormats.contains(item.fileFormat) { return false }
        if !sourceIDs.isEmpty, !sourceIDs.contains(item.sourceID) { return false }

        if let range = dateRange {
            // Compare on day granularity so the end day is inclusive and a
            // single-day pick (start == end) still matches that whole day.
            guard let date = item.captureDate else { return false }
            let day = date.dayStart
            if day < range.lowerBound.dayStart || day > range.upperBound.dayStart { return false }
        }

        let q = locationQuery.trimmingCharacters(in: .whitespaces)
        if !q.isEmpty {
            guard let name = item.locationName,
                  name.localizedCaseInsensitiveContains(q) else { return false }
        }

        switch tagFilter {
        case .any: break
        case .tagged: if item.tagIDs.isEmpty { return false }
        case .untagged: if !item.tagIDs.isEmpty { return false }
        }

        if !tagIDs.isEmpty, item.tagIDs.isDisjoint(with: tagIDs) { return false }

        if let projectID, !item.projectIDs.contains(projectID) { return false }

        // Discarded clips are hidden unless explicitly shown (non-destructive —
        // the file is untouched, only the suggestion is hidden).
        if !showDiscarded, item.isDiscarded { return false }

        if !contentTags.isEmpty, item.effectiveContentTags.isDisjoint(with: contentTags) {
            return false
        }

        switch flagFilter {
        case .any: break
        case .flagged: if item.qualityFlags.isEmpty { return false }
        case .mistakes: if !item.qualityFlags.contains(where: { $0.isMistake }) { return false }
        case .clean: if !item.qualityFlags.isEmpty { return false }
        }

        switch analysisFilter {
        case .any: break
        case .analyzed: if item.analysis == nil { return false }
        case .notAnalyzed: if item.analysis != nil { return false }
        case .aiEnriched: if item.analysis?.apiModel == nil { return false }
        }

        return true
    }

    /// Stable comparator honoring sortKey + direction. nil values sort last.
    func areInOrder(_ a: MediaItem, _ b: MediaItem) -> Bool {
        let ascending = sortDirection == .ascending
        func order<T: Comparable>(_ x: T, _ y: T) -> Bool { ascending ? x < y : x > y }

        switch sortKey {
        case .date:
            let da = a.captureDate ?? .distantPast
            let db = b.captureDate ?? .distantPast
            if da == db { return a.filename < b.filename }
            return order(da, db)
        case .fileSize:
            if a.fileSize == b.fileSize { return a.filename < b.filename }
            return order(a.fileSize, b.fileSize)
        case .duration:
            let xa = a.duration ?? 0
            let xb = b.duration ?? 0
            if xa == xb { return a.filename < b.filename }
            return order(xa, xb)
        case .camera:
            let ca = a.cameraLabel, cb = b.cameraLabel
            if ca == cb { return order(a.captureDate ?? .distantPast, b.captureDate ?? .distantPast) }
            return order(ca, cb)
        case .location:
            let la = a.locationName ?? "\u{10FFFF}"   // push unknowns to the end
            let lb = b.locationName ?? "\u{10FFFF}"
            if la == lb { return order(a.captureDate ?? .distantPast, b.captureDate ?? .distantPast) }
            return order(la, lb)
        }
    }
}
