import Cocoa

final class DocumentViewController: NSViewController {
    weak var document: AtlasDocument? {
        didSet {
            if let index = document?.codeIndex {
                treemapView.load(index: index)
            }
        }
    }

    private var fileLabel: NSTextField!
    private var metricPopup: NSPopUpButton!
    private var metricsLabel: NSTextField!
    private var nameLabel: NSTextField!
    private var treemapView: TreemapView!

    override func viewDidLoad() {
        super.viewDidLoad()

        nameLabel = NSTextField(labelWithString: "")
        nameLabel.font = .preferredFont(forTextStyle: .headline)
        nameLabel.textColor = .labelColor
        nameLabel.lineBreakMode = .byTruncatingTail
        nameLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        metricsLabel = NSTextField(labelWithString: "")
        metricsLabel.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        metricsLabel.textColor = .secondaryLabelColor

        fileLabel = NSTextField(labelWithString: "")
        fileLabel.font = .preferredFont(forTextStyle: .body)
        fileLabel.textColor = .secondaryLabelColor
        fileLabel.lineBreakMode = .byTruncatingTail
        fileLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let labelStack = NSStackView(views: [nameLabel, fileLabel, metricsLabel])
        labelStack.orientation = .vertical
        labelStack.alignment = .leading
        labelStack.spacing = 2
        labelStack.setContentHuggingPriority(.defaultLow, for: .horizontal)

        metricPopup = NSPopUpButton()
        Metric.allCases.forEach { metricPopup.addItem(withTitle: $0.rawValue) }
        metricPopup.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        metricPopup.target = self
        metricPopup.action = #selector(metricChanged(_:))

        let modeControl = NSSegmentedControl(
            labels: ["Complexity", "Structure"],
            trackingMode: .selectOne,
            target: self,
            action: #selector(modeChanged)
        )
        modeControl.selectedSegment = 0

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        spacer.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let topBar = NSStackView(views: [labelStack, spacer, metricPopup, modeControl])
        topBar.orientation = .horizontal
        topBar.alignment = .centerY
        topBar.distribution = .fill
        topBar.spacing = 12
        topBar.setContentHuggingPriority(.defaultHigh, for: .vertical)

        treemapView = TreemapView(frame: .zero)
        treemapView.onHover = { [weak self] node in
            guard let self else { return }
            self.nameLabel.stringValue = node?.name ?? ""
            self.fileLabel.stringValue = node?.filePath ?? ""
            self.metricsLabel.stringValue = node?.metricsDescription ?? ""
        }

        let rootStack = NSStackView(views: [topBar, treemapView])
        rootStack.orientation = .vertical
        rootStack.alignment = .leading
        rootStack.spacing = 8
        rootStack.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(rootStack)
        NSLayoutConstraint.activate([
            rootStack.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
            rootStack.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor),
            rootStack.topAnchor.constraint(equalTo: view.layoutMarginsGuide.topAnchor),
            rootStack.bottomAnchor.constraint(equalTo: view.layoutMarginsGuide.bottomAnchor),
        ])
    }

    @objc private func metricChanged(_ sender: NSPopUpButton) {
        treemapView.metric = Metric.allCases[sender.indexOfSelectedItem]
    }

    @objc private func modeChanged(_ sender: NSSegmentedControl) {
        let mode: ViewMode = sender.selectedSegment == 0 ? .complexity : .structure
        treemapView.viewMode = mode
        switch mode {
        case .complexity:
            metricPopup.isHidden = false
        case .structure:
            metricPopup.isHidden = true            
        }
    }
}

private extension DisplayNode {
    var name: String { node.name }
    var filePath: String? { node.filePath.map { "\($0):\(node.startLine)" } }
    var metricsDescription: String? {
        var parts = [String]()
        parts.append("cyclomatic \(Int(node.cyclomaticComplexity))")
        parts.append("cognitive \(Int(node.cognitiveComplexity))")
        parts.append("nesting \(Int(node.nestingDepth))")
        parts.append("params \(Int(node.parameterCount))")
        return parts.joined(separator: ", ")
    }
}
