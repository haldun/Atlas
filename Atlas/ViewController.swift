import Cocoa

final class ViewController: NSViewController {
    weak var document: AtlasDocument? {
        didSet {
            if let index = document?.codeIndex {
                treemapView.load(index: index)
            }
        }
    }

    private var treemapView: TreemapView!
    private var metricPopup: NSPopUpButton!

    override func viewDidLoad() {
        super.viewDidLoad()

        let nameLabel = NSTextField(labelWithString: "")
        nameLabel.font = .preferredFont(forTextStyle: .headline)
        nameLabel.textColor = .labelColor

        let metricsLabel = NSTextField(labelWithString: "")
        metricsLabel.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        metricsLabel.textColor = .secondaryLabelColor

        let fileLabel = NSTextField(labelWithString: "")
        fileLabel.font = .preferredFont(forTextStyle: .body)
        fileLabel.textColor = .secondaryLabelColor

        let labelStack = NSStackView(views: [nameLabel, fileLabel, metricsLabel])
        labelStack.orientation = .vertical
        labelStack.alignment = .leading
        labelStack.spacing = 2
        labelStack.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let metricPopup = NSPopUpButton()
        Metric.allCases.forEach { metricPopup.addItem(withTitle: $0.rawValue) }
        metricPopup.setContentHuggingPriority(.defaultHigh, for: .horizontal)

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        spacer.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let topBar = NSStackView(views: [labelStack, spacer, metricPopup])
        topBar.orientation = .horizontal
        topBar.alignment = .centerY
        topBar.distribution = .fill
        topBar.spacing = 12
        topBar.setContentHuggingPriority(.defaultHigh, for: .vertical)

        let treemapView = TreemapView(frame: .zero)

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

        treemapView.onHover = { node in
            nameLabel.stringValue = node?.name ?? ""
            fileLabel.stringValue = node?.filePath ?? ""
            metricsLabel.stringValue = node?.metricsDescription ?? ""
        }

        metricPopup.target = self
        metricPopup.action = #selector(metricChanged(_:))
        self.metricPopup = metricPopup
        self.treemapView = treemapView
    }

    @objc private func metricChanged(_ sender: NSPopUpButton) {
        let metric = Metric.allCases[sender.indexOfSelectedItem]
        treemapView.selectMetric(metric)
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
