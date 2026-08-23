//
//  Tag.swift
//  The Vault
//
//  Color-coded labels applied to media. Tags can be global or scoped to a
//  project (projectID != nil). Used for batch tagging and filtering.
//

import Foundation
import SwiftUI

struct Tag: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String

    /// Stored as a hex string so the model stays Codable and UI-framework neutral.
    var colorHex: String

    /// If set, this tag belongs to a single project; otherwise it is global.
    var projectID: UUID?

    var createdAt: Date

    var isGlobal: Bool { projectID == nil }

    var color: Color { Color(hex: colorHex) ?? .accentColor }

    init(id: UUID = UUID(),
         name: String,
         colorHex: String = "#FFB020",
         projectID: UUID? = nil,
         createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.colorHex = colorHex
        self.projectID = projectID
        self.createdAt = createdAt
    }

    static func == (lhs: Tag, rhs: Tag) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

extension Tag {
    /// A small palette offered in the tag editor.
    static let palette: [String] = [
        "#FFB020", // amber
        "#FF5470", // rose
        "#4ECDC4", // teal
        "#5B8DEF", // blue
        "#A88BEB", // violet
        "#7DD957", // green
        "#FF8A5B", // orange
        "#9AA0A6"  // grey
    ]

    static var defaults: [Tag] {
        [
            Tag(name: "Hero Shot", colorHex: "#FFB020"),
            Tag(name: "B-Roll", colorHex: "#4ECDC4"),
            Tag(name: "Selects", colorHex: "#7DD957"),
            Tag(name: "Unusable", colorHex: "#FF5470")
        ]
    }
}
