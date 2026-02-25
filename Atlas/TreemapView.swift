import Cocoa

enum Metric: String, CaseIterable {
    case cyclomatic = "Cyclomatic Complexity"
    case cognitive = "Cognitive Complexity"
    case nesting = "Nesting Depth"
    case parameters = "Parameter Count"
}

final class TreemapView: NSView {
    var display: TreeMapDisplay = TreeMapDisplay(nodes: [])
    private var selectedMetric: Metric = .cyclomatic
    private var zoomLevel: CGFloat = 1.0
    private var panOffset: CGPoint = .zero

    var onHover: ((DisplayNode?) -> Void)?

    private var hoveredNode: DisplayNode? = nil {
        didSet {
            guard hoveredNode != oldValue else { return }
            onHover?(hoveredNode)
            needsDisplay = true
        }
    }

    private var codeIndex: CodeIndex? = nil
    private var trackingArea: NSTrackingArea?

    override init(frame: NSRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        wantsLayer = true
        layer?.backgroundColor = NSColor(white: 0.12, alpha: 1).cgColor

        let click = NSClickGestureRecognizer(target: self, action: #selector(handleClick))
        click.numberOfClicksRequired = 1
        addGestureRecognizer(click)

        let pan = NSPanGestureRecognizer(target: self, action: #selector(handlePan))
        addGestureRecognizer(pan)
    }

    @objc private func handleClick(_ gesture: NSClickGestureRecognizer) {
        let point = gesture.location(in: self)
        if let node = hitTest(point: point), let path = node.node.filePath {
            Process.launchedProcess(launchPath: "/usr/bin/xed", arguments: ["--line", "\(node.node.startLine)", path])
        }
    }

    @objc private func handlePan(_ gesture: NSPanGestureRecognizer) {
        let delta = gesture.translation(in: self)
        let oldPanOffset = panOffset
        panOffset.x += delta.x
        panOffset.y += delta.y
        clampPanOffset()
        if oldPanOffset == panOffset { return }
        gesture.setTranslation(.zero, in: self)
        hoveredNode = nil
        relayout()
    }

    private func clampPanOffset() {
        // clamp pan so we always cover the view bounds
        panOffset.x = min(0, max(panOffset.x, bounds.width - bounds.width * zoomLevel))
        panOffset.y = min(0, max(panOffset.y, bounds.height - bounds.height * zoomLevel))
    }

    func load(index: CodeIndex) {
        codeIndex = index
        relayout()
    }

    func selectMetric(_ metric: Metric) {
        selectedMetric = metric
        buildGradientCache()
        needsDisplay = true
    }

    override var isFlipped: Bool { true }

    override func layout() {
        super.layout()
        if codeIndex != nil { relayout() }
    }

    private func treemapRect() -> CGRect {
        CGRect(
            x: panOffset.x,
            y: panOffset.y,
            width: bounds.width * zoomLevel,
            height: bounds.height * zoomLevel
        )
    }

    private func relayout() {
        guard let index = codeIndex else { return }
        display = layoutTreemap(root: index.root, in: treemapRect())
        buildGradientCache()
        needsDisplay = true
    }

    private var cachedGradients: [CGRect: CGGradient] = [:]

    private func buildGradientCache() {
        cachedGradients.removeAll()
        for node in display.nodes where node.node.isLeaf {
            let heat = heatColor(for: metricValue(for: node.node, metric: selectedMetric), metric: selectedMetric)
            let highlight = heat.lighter(by: 0.12)
            if let gradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: [highlight.cgColor, heat.cgColor] as CFArray,
                locations: [0, 1]
            ) {
                cachedGradients[node.frame] = gradient
            }
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }

        ctx.setFillColor(CGColor(gray: 0.12, alpha: 1))
        ctx.fill(bounds)
        ctx.saveGState()
        ctx.clip(to: bounds)

        for node in display.nodes.reversed() {
            let frame = node.frame
            guard frame.width > 1, frame.height > 1, node.node.isLeaf else { continue }
            guard let gradient = cachedGradients[node.frame] else { continue }
            ctx.saveGState()
            ctx.clip(to: frame)
            ctx.drawRadialGradient(
                gradient,
                startCenter: CGPoint(x: frame.midX, y: frame.midY),
                startRadius: 0,
                endCenter: CGPoint(x: frame.midX, y: frame.midY),
                endRadius: max(frame.width, frame.height) * 0.7,
                options: [.drawsAfterEndLocation]
            )
            ctx.restoreGState()
        }

        for node in display.nodes.reversed() {
            let frame = node.frame
            guard frame.width > 1, frame.height > 1, !node.node.isLeaf else { continue }
            switch node.node.kind {
            case .folder: ctx.setStrokeColor(CGColor(gray: 0, alpha: 1))
            case .file: ctx.setStrokeColor(CGColor(gray: 0.14, alpha: 1))
            default: continue
            }
            ctx.setLineWidth(1)
            ctx.stroke(frame.insetBy(dx: 0.5, dy: 0.5))
        }

        if let hovered = hoveredNode {
            ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 0.4, alpha: 1))
            ctx.setLineWidth(2)
            ctx.stroke(hovered.frame)
        }

        ctx.restoreGState()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingArea { removeTrackingArea(existing) }
        trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.activeInKeyWindow, .mouseMoved],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea!)
    }

    override func mouseMoved(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        hoveredNode = hitTest(point: point)
    }

    private func hitTest(point: CGPoint) -> DisplayNode? {
        var best: DisplayNode? = nil
        for node in display.nodes {
            if node.frame.contains(point) { best = node }
        }
        return best
    }

    override func scrollWheel(with event: NSEvent) {
        let mouse = convert(event.locationInWindow, from: nil)
        let factor: CGFloat = event.scrollingDeltaY > 0 ? 1.1 : 1 / 1.1
        let oldZoom = zoomLevel
        zoomLevel = max(1.0, min(20.0, zoomLevel * factor))
        if zoomLevel == 1.0 {
            panOffset = .zero
        } else {
            let scale = zoomLevel / oldZoom
            panOffset.x = mouse.x - scale * (mouse.x - panOffset.x)
            panOffset.y = mouse.y - scale * (mouse.y - panOffset.y)
        }
        if oldZoom == zoomLevel { return }
        clampPanOffset()
        hoveredNode = nil
        relayout()
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        hoveredNode = nil
    }

    override var acceptsFirstResponder: Bool { true }
}

private func metricValue(for node: TreeNode, metric: Metric) -> Float {
    switch metric {
    case .cyclomatic: node.cyclomaticComplexity
    case .cognitive: node.cognitiveComplexity
    case .nesting: node.nestingDepth
    case .parameters: node.parameterCount
    }
}

private func heatColor(for value: Float, metric: Metric) -> NSColor {
    switch metric {
    case .cyclomatic: color(value, low: 10, high: 25)
    case .cognitive: color(value, low: 7, high: 15)
    case .nesting: color(value, low: 2, high: 5)
    case .parameters: color(value, low: 3, high: 6)
    }
}

private func color(_ value: Float, low: Float, high: Float) -> NSColor {
    let sand = NSColor(red: 0.93, green: 0.86, blue: 0.76, alpha: 1)
    let amber = NSColor(red: 0.82, green: 0.63, blue: 0.39, alpha: 1)
    let terracotta = NSColor(red: 0.73, green: 0.37, blue: 0.27, alpha: 1)

    switch value {
    case ..<low: return lerp(sand, amber, CGFloat(value / low))
    case ..<high: return lerp(amber, terracotta, CGFloat((value - low) / (high - low)))
    default: return terracotta
    }
}

private func lerp(_ a: NSColor, _ b: NSColor, _ t: CGFloat) -> NSColor {
    NSColor(
        red: a.redComponent + (b.redComponent - a.redComponent) * t,
        green: a.greenComponent + (b.greenComponent - a.greenComponent) * t,
        blue: a.blueComponent + (b.blueComponent - a.blueComponent) * t,
        alpha: 1
    )
}

extension NSColor {
    func lighter(by amount: CGFloat) -> NSColor {
        guard let rgb = usingColorSpace(.deviceRGB) else { return self }
        return NSColor(
            red: min(rgb.redComponent + amount, 1),
            green: min(rgb.greenComponent + amount, 1),
            blue: min(rgb.blueComponent + amount, 1),
            alpha: rgb.alphaComponent
        )
    }
}

extension DisplayNode {
    fileprivate var name: String { node.name }
    fileprivate var filePath: String? { node.filePath.map { "\($0):\(node.startLine)" } }
    fileprivate var metricsDescription: String? {
        var parts = [String]()
        parts.append("cyclomatic \(Int(node.cyclomaticComplexity))")
        parts.append("cognitive \(Int(node.cognitiveComplexity))")
        parts.append("nesting \(Int(node.nestingDepth))")
        parts.append("params \(Int(node.parameterCount))")
        return parts.joined(separator: ", ")
    }
}
