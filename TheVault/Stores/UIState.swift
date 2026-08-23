//
//  UIState.swift
//  The Vault
//
//  Small shared UI enums used across the sidebar, toolbar, and browser.
//

import Foundation

/// Top-level app screen. The app is projects-first: it opens on Home.
enum AppRoute: Hashable {
    case home
    case browser   // the 3-pane library browser (sources / grid / detail)
}

/// When a project is selected, which pool of media the browser shows.
enum ProjectScope: String, CaseIterable, Identifiable {
    case inProject = "In Project"
    case sourceMedia = "All Source Media"
    var id: String { rawValue }

    var symbolName: String {
        switch self {
        case .inProject: return "checkmark.circle"
        case .sourceMedia: return "externaldrive"
        }
    }
}

/// What the sidebar has selected — scopes the browser contents.
enum SidebarSelection: Hashable {
    case allMedia
    case untagged
    case source(UUID)
    case project(UUID)
    case tag(UUID)
}

/// The three primary ways to view media.
enum BrowserViewMode: String, CaseIterable, Identifiable {
    case grid = "Grid"
    case timeline = "Timeline"
    case map = "Map"

    var id: String { rawValue }

    var symbolName: String {
        switch self {
        case .grid: return "square.grid.2x2"
        case .timeline: return "calendar.day.timeline.left"
        case .map: return "map"
        }
    }
}
