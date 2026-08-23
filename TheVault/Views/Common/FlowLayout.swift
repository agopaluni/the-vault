//
//  FlowLayout.swift
//  The Vault
//
//  A simple wrapping layout (left-to-right, wrapping to new rows) used for tag
//  and project chips. Built on the macOS 13 `Layout` protocol.
//

import SwiftUI

struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize,
                      subviews: Subviews, cache: inout Void) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        let rows = layout(subviews: subviews, maxWidth: maxWidth)
        let height = rows.last.map { $0.y + $0.rowHeight } ?? 0
        let widest = rows.map { row in
            (row.items.last.map { $0.x + $0.size.width } ?? 0)
        }.max() ?? 0
        return CGSize(width: maxWidth == .infinity ? widest : maxWidth, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize,
                       subviews: Subviews, cache: inout Void) {
        let rows = layout(subviews: subviews, maxWidth: bounds.width)
        for row in rows {
            for placement in row.items {
                let pt = CGPoint(x: bounds.minX + placement.x,
                                 y: bounds.minY + row.y)
                placement.subview.place(at: pt, anchor: .topLeading,
                                        proposal: ProposedViewSize(placement.size))
            }
        }
    }

    // MARK: Row computation

    private struct Placement { let subview: LayoutSubview; let size: CGSize; let x: CGFloat }
    private struct Row { var y: CGFloat; var rowHeight: CGFloat; var items: [Placement] }

    private func layout(subviews: Subviews, maxWidth: CGFloat) -> [Row] {
        var rows: [Row] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var current: [Placement] = []

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, !current.isEmpty {
                rows.append(Row(y: y, rowHeight: rowHeight, items: current))
                current.removeAll()
                y += rowHeight + spacing
                x = 0
                rowHeight = 0
            }
            current.append(Placement(subview: subview, size: size, x: x))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        if !current.isEmpty { rows.append(Row(y: y, rowHeight: rowHeight, items: current)) }
        return rows
    }
}
