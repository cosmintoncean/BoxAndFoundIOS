import SwiftUI

/// Lays chips out left to right, wrapping onto the next line when the row runs
/// out of width.
///
/// Written rather than scrolled. The first two attempts at the tag bar put a
/// horizontal `ScrollView` above the list — once in a `VStack`, once as a
/// safe-area inset — and both laid the chips out correctly, hit-tested them
/// correctly, and drew nothing at all. The element tree from CI showed them on
/// screen at sensible frames with two full-size system layers sharing their
/// rectangle, which is as far as a machine with no Xcode can take that.
///
/// So the bar is built from pieces this screen is known to draw: a list row, an
/// `HStack`, a `Capsule`. Wrapping also suits the content better than scrolling
/// did — tags are short, and a household has a handful rather than a hundred,
/// so showing them all beats hiding most of them off the right edge.
struct TagFlow: Layout {
    var spacing: CGFloat = 8
    var lineSpacing: CGFloat = 8

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        let width = proposal.width ?? .infinity
        let rows = arrange(subviews, within: width)
        let height = rows.reduce(0.0) { $0 + $1.height } +
            lineSpacing * Double(max(0, rows.count - 1))
        return CGSize(width: proposal.width ?? rows.map(\.width).max() ?? 0, height: height)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        var y = bounds.minY
        for row in arrange(subviews, within: bounds.width) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(
                    at: CGPoint(x: x, y: y),
                    anchor: .topLeading,
                    proposal: ProposedViewSize(size)
                )
                x += size.width + spacing
            }
            y += row.height + lineSpacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var width: Double = 0
        var height: Double = 0
    }

    private func arrange(_ subviews: Subviews, within width: Double) -> [Row] {
        var rows: [Row] = []
        var current = Row()

        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let needed = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            if needed > width, !current.indices.isEmpty {
                rows.append(current)
                current = Row()
                current.indices = [index]
                current.width = size.width
                current.height = size.height
            } else {
                current.indices.append(index)
                current.width = needed
                current.height = max(current.height, size.height)
            }
        }

        if !current.indices.isEmpty { rows.append(current) }
        return rows
    }
}
