import Cocoa

final class AtlasDocumentController: NSDocumentController {
    override func newDocument(_ sender: Any?) {
        guard let folderURL = askForFolder() else { return }
        Task {
            do {
                let doc = AtlasDocument()
                doc.codeIndex = try makeIndex(at: folderURL)
                addDocument(doc)
                doc.makeWindowControllers()
                doc.showWindows()
            } catch {
                NSAlert(error: error).runModal()
            }
        }
    }
}

class AtlasDocument: NSDocument {
    var codeIndex: CodeIndex?

    override nonisolated class var autosavesInPlace: Bool { true }

    override func makeWindowControllers() {
        let storyboard = NSStoryboard(name: NSStoryboard.Name("Main"), bundle: nil)
        let windowController =
            storyboard.instantiateController(withIdentifier: NSStoryboard.SceneIdentifier("Document Window Controller"))
            as! NSWindowController
        addWindowController(windowController)
        if let viewController = windowController.contentViewController as? DocumentViewController {
            viewController.document = self
        }
    }

    override func data(ofType typeName: String) throws -> Data {
        guard let index = codeIndex else { throw NSError(domain: NSOSStatusErrorDomain, code: unimpErr) }
        return try JSONEncoder().encode(index)
    }

    override nonisolated func read(from data: Data, ofType typeName: String) throws {
        let index = try JSONDecoder().decode(CodeIndex.self, from: data)
        Task { @MainActor in
            self.codeIndex = index
            (self.windowControllers.first?.contentViewController as? DocumentViewController)?.document = self
        }
    }
}

private func askForFolder() -> URL? {
    let panel = NSOpenPanel()
    panel.canChooseFiles = false
    panel.canChooseDirectories = true
    panel.allowsMultipleSelection = false
    panel.message = "Choose a Swift project folder to index"
    panel.prompt = "Open"
    return panel.runModal() == .OK ? panel.url : nil
}
