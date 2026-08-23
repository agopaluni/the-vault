//
//  Project.swift
//  The Vault
//
//  A named collection of media (e.g. "Tokyo Vlog", "Wedding Photos").
//  Media can belong to multiple projects. Projects keep an explicit ordered
//  list of member item IDs so the user can reorder within a project view.
//

import Foundation
import SwiftUI

/// Free-form-ish project type used for the user's own organization.
enum ProjectType: String, Codable, CaseIterable {
    case vlog
    case photoEdit
    case film
    case bRoll
    case social
    case other

    var displayName: String {
        switch self {
        case .vlog: return "Vlog"
        case .photoEdit: return "Photo Edit"
        case .film: return "Film"
        case .bRoll: return "B-Roll"
        case .social: return "Social"
        case .other: return "Other"
        }
    }

    var symbolName: String {
        switch self {
        case .vlog: return "video"
        case .photoEdit: return "photo.on.rectangle"
        case .film: return "film"
        case .bRoll: return "rectangle.stack"
        case .social: return "bubble.left.and.bubble.right"
        case .other: return "folder"
        }
    }

    var accentHex: String {
        switch self {
        case .vlog: return "#FFB020"
        case .photoEdit: return "#4ECDC4"
        case .film: return "#FF5470"
        case .bRoll: return "#5B8DEF"
        case .social: return "#A88BEB"
        case .other: return "#9AA0A6"
        }
    }
}

struct Project: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var type: ProjectType

    /// Ordered member item IDs — order is meaningful (reorderable in project view).
    var orderedItemIDs: [UUID]

    var createdAt: Date
    var updatedAt: Date

    var itemCount: Int { orderedItemIDs.count }

    init(id: UUID = UUID(),
         name: String,
         type: ProjectType = .other,
         orderedItemIDs: [UUID] = [],
         createdAt: Date = Date(),
         updatedAt: Date = Date()) {
        self.id = id
        self.name = name
        self.type = type
        self.orderedItemIDs = orderedItemIDs
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    static func == (lhs: Project, rhs: Project) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }

    mutating func add(_ itemID: UUID) {
        guard !orderedItemIDs.contains(itemID) else { return }
        orderedItemIDs.append(itemID)
        updatedAt = Date()
    }

    mutating func remove(_ itemID: UUID) {
        orderedItemIDs.removeAll { $0 == itemID }
        updatedAt = Date()
    }
}
