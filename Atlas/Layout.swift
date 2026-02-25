import QuartzCore

// Here we implement tree map layout algorithm.
struct DisplayNode: Equatable {
    let node: TreeNode
    var frame: CGRect
}

struct TreeMapDisplay {
    var nodes: [DisplayNode]
}

func layoutTreemap(root: TreeNode, in bounds: CGRect) -> TreeMapDisplay {
    var result: [DisplayNode] = []
    layoutNode(root, in: bounds, output: &result)
    return TreeMapDisplay(nodes: result)
}

private func layoutNode(_ node: TreeNode, in frame: CGRect, output: inout [DisplayNode]) {
    let snapped = snap(frame)
    output.append(DisplayNode(node: node, frame: snapped))
    if node.children.isEmpty { return }
    if frame.width > 1 && frame.height > 1 {
        squarify(nodes: node.children, in: frame, output: &output)
    }
}

private func squarify(nodes: [TreeNode], in rect: CGRect, output: inout [DisplayNode]) {
    var totalSize: CGFloat = 0
    var remaining: [(TreeNode, CGFloat)] = []
    for node in nodes {
        guard node.size > 0 else { continue }
        totalSize += CGFloat(node.size)
        remaining.append((node, 0))  // area will be computed later
    }
    guard totalSize > 0 else { return }
    let rectArea = rect.width * rect.height
    for i in remaining.indices {
        remaining[i].1 = (CGFloat(remaining[i].0.size) / totalSize) * rectArea
    }

    var row: [(TreeNode, CGFloat)] = []
    var rect = rect
    var index = 0

    while index < remaining.count {
        let next = remaining[index]
        let shortSide = min(rect.width, rect.height)
        if row.isEmpty || worstRatio(row + [next], side: shortSide) <= worstRatio(row, side: shortSide) {
            row.append(next)
            index += 1
        } else {
            layoutRow(row, in: &rect, output: &output)
            row.removeAll(keepingCapacity: true)
        }
    }
    if !row.isEmpty {
        layoutRow(row, in: &rect, output: &output)
    }
}

private func worstRatio(_ areas: [(TreeNode, CGFloat)], side: CGFloat) -> CGFloat {
    var minA: CGFloat = .greatestFiniteMagnitude
    var maxA: CGFloat = 0
    var sum: CGFloat = 0
    for (_, a) in areas {
        sum += a
        minA = min(minA, a)
        maxA = max(maxA, a)
    }
    let s2 = side * side
    let sum2 = sum * sum
    return max((s2 * maxA) / sum2, sum2 / (s2 * minA))
}

private func layoutRow(_ row: [(TreeNode, CGFloat)], in rect: inout CGRect, output: inout [DisplayNode]) {
    let rowArea: CGFloat = row.reduce(0) { $0 + $1.1 }
    let horizontal = rect.width >= rect.height
    let shortSide = horizontal ? rect.height : rect.width
    let thickness = rowArea / shortSide
    var offset: CGFloat = 0

    for (node, area) in row {
        let extent = area / thickness
        let frame: CGRect
        if horizontal {
            frame = CGRect(x: rect.minX, y: rect.minY + offset, width: thickness, height: extent)
        } else {
            frame = CGRect(x: rect.minX + offset, y: rect.minY, width: extent, height: thickness)
        }
        layoutNode(node, in: frame, output: &output)
        offset += extent
    }

    if horizontal {
        rect.origin.x += thickness
        rect.size.width -= thickness
    } else {
        rect.origin.y += thickness
        rect.size.height -= thickness
    }
}

@inline(__always)
private func snap(_ r: CGRect) -> CGRect {
    let x = floor(r.origin.x)
    let y = floor(r.origin.y)
    let w = ceil(r.origin.x + r.size.width) - x
    let h = ceil(r.origin.y + r.size.height) - y
    return CGRect(x: x, y: y, width: w, height: h)
}
