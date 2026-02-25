import Foundation
import SwiftParser
import SwiftSyntax

nonisolated struct CodeIndex: Codable, Sendable {
    let root: TreeNode
}

nonisolated struct TreeNode: Codable, Equatable, Sendable {
    // @todo which node kinds should have metrics? maybe it does not make sense to have class/struct/etc to be nodes at all?
    // @todo currently we think that method/freeFunction/globalVariable is the smallest code unit that a metric would make sense.
    // But maybe it is not always the case? What would be a different way of looking at the code?

    // @todo how to handle the nested functions? should they be just child nodes?
    enum Kind: Codable, Equatable {
        case folder
        case file
        case `enum`
        case `protocol`
        case `class`
        case `struct`
        case method
        case freeFunction
        // case globalVariable
        // @todo handle the following at a point
        // actor, extension, globalVariable, property
    }

    let name: String
    let kind: Kind
    var size: Float = 0.0
    var selectedMetric: Float { cognitiveComplexity }
    var cyclomaticComplexity: Float = 0.0
    var cognitiveComplexity: Float = 0.0
    var nestingDepth: Float = 0.0
    var parameterCount: Float = 0.0
    var startLine: Int = 0
    var endLine: Int = 0
    var filePath: String? = nil
    // @todo this is probably not good, but we currently do not care.
    // @todo it would be great if we can have an easy way to acces to the parent node.
    var children: [TreeNode] = []
    var isLeaf: Bool { children.isEmpty }
}

func validate(_ node: TreeNode) -> Bool {
    if node.size < 0 { return false }
    if node.isLeaf { return true }
    for child in node.children { if !validate(child) { return false } }
    return node.size == node.children.reduce(0.0) { $0 + $1.size }
}

nonisolated func makeIndex(at url: URL) throws -> CodeIndex {
    guard let root = try buildTree(from: url) else { throw CodeIndexError.failedToReadFolder }
    if !validate(root) { preconditionFailure("The tree that we built is not valid. This is a bug") }
    return .init(root: root)
}

enum CodeIndexError: Swift.Error {
    case failedToReadFolder
}

func parse(at url: URL) -> [TreeNode] {
    guard let source = try? String(contentsOf: url, encoding: .utf8) else { return [] }
    let sourceFile = Parser.parse(source: source)
    let converter = SourceLocationConverter(fileName: url.path, tree: sourceFile)
    let visitor = DeclarationVisitor(converter: converter, filePath: url.path, viewMode: .sourceAccurate)
    visitor.walk(sourceFile)
    return visitor.nodes
}

func buildTree(from url: URL) throws -> TreeNode? {
    let fm = FileManager.default
    let values = try url.resourceValues(forKeys: [
        .isDirectoryKey, .isRegularFileKey, .fileSizeKey, .isSymbolicLinkKey,
    ])
    if values.isSymbolicLink == true { return nil }
    // handle a swift file
    if values.isRegularFile == true {
        guard url.pathExtension == "swift" else { return nil }
        let children = parse(at: url)
        if children.isEmpty { return nil }
        return TreeNode(
            name: url.lastPathComponent,
            kind: .file,
            size: children.reduce(0.0) { $0 + $1.size },
            filePath: url.path,
            children: children
        )
    }
    // handle a directory
    if values.isDirectory == true {
        let contents = try fm.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey, .fileSizeKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        )
        let children = try contents.compactMap { try buildTree(from: $0) }
        if children.isEmpty { return nil }
        return TreeNode(
            name: url.lastPathComponent,
            kind: .folder,
            size: children.reduce(0.0) { $0 + $1.size },
            children: children
        )
    }
    return nil
}

nonisolated final class DeclarationVisitor: SyntaxVisitor {
    nonisolated(unsafe) var nodes: [TreeNode] = []
    let converter: SourceLocationConverter
    let filePath: String

    nonisolated init(converter: SourceLocationConverter, filePath: String, viewMode: SyntaxTreeViewMode) {
        self.converter = converter
        self.filePath = filePath
        super.init(viewMode: viewMode)
    }

    override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        nodes.append(makeNode(from: node, kind: .class))
        return .skipChildren
    }

    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        nodes.append(makeNode(from: node, kind: .struct))
        return .skipChildren
    }

    override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
        nodes.append(makeNode(from: node, kind: .enum))
        return .skipChildren
    }

    override func visit(_ node: ProtocolDeclSyntax) -> SyntaxVisitorContinueKind {
        nodes.append(makeNode(from: node, kind: .protocol))
        return .skipChildren
    }

    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        let isMethod = node.parent?.is(MemberBlockItemSyntax.self) == true
        let (start, end) = lines(of: node)
        nodes.append(
            .init(
                name: node.name.text,
                kind: isMethod ? .method : .freeFunction,
                size: size(of: node),
                cyclomaticComplexity: Float(cyclomatic(of: node)),
                cognitiveComplexity: Float(cognitive(of: node)),
                nestingDepth: Float(nestingDepth(of: node)),
                parameterCount: Float(parameterCount(of: node)),
                startLine: start,
                endLine: end,
                filePath: filePath
            )
        )
        return .skipChildren
    }

    override func visit(_ node: InitializerDeclSyntax) -> SyntaxVisitorContinueKind {
        let (start, end) = lines(of: node)
        let labels = node.signature.parameterClause.parameters.map {
            $0.firstName.text == "_" ? "_:" : $0.firstName.text + ":"
        }.joined()
        let name = "init(\(labels))"
        nodes.append(
            .init(
                name: name,
                kind: .method,
                size: size(of: node),
                cyclomaticComplexity: Float(cyclomatic(of: node)),
                cognitiveComplexity: Float(cognitive(of: node)),
                nestingDepth: Float(nestingDepth(of: node)),
                parameterCount: Float(parameterCount(of: node)),
                startLine: start,
                endLine: end,
                filePath: filePath
            )
        )
        return .skipChildren
    }

    private func makeNode<D: NamedDeclSyntax & DeclGroupSyntax>(from decl: D, kind: TreeNode.Kind) -> TreeNode {
        let visitor = DeclarationVisitor(converter: converter, filePath: filePath, viewMode: .sourceAccurate)
        visitor.walk(decl.memberBlock)
        let children = visitor.nodes
        let (start, end) = lines(of: decl)
        return TreeNode(
            name: decl.name.text,
            kind: kind,
            size: children.reduce(0.0) { $0 + $1.size },
            startLine: start,
            endLine: end,
            filePath: filePath,
            children: children
        )
    }

    private func lines(of node: some SyntaxProtocol) -> (Int, Int) {
        let start = converter.location(for: node.positionAfterSkippingLeadingTrivia)
        let end = converter.location(for: node.endPositionBeforeTrailingTrivia)
        return (start.line, end.line)
    }
}

// this returns number of AST nodes within the node.
nonisolated func size(of node: some SyntaxProtocol) -> Float {
    Float(node.tokens(viewMode: .sourceAccurate).reduce(0) { acc, _ in acc + 1 })
}

nonisolated func cyclomatic(of function: WithOptionalCodeBlockSyntax) -> Int {
    guard let body = function.body else { return 1 }
    final class Visitor: SyntaxVisitor {
        var result = 1
        override func visitPost(_ node: ForStmtSyntax) { result += 1 }
        override func visitPost(_ node: GuardStmtSyntax) { result += 1 }
        override func visitPost(_ node: IfExprSyntax) { result += 1 }
        override func visitPost(_ node: RepeatStmtSyntax) { result += 1 }
        override func visitPost(_ node: WhileStmtSyntax) { result += 1 }
        override func visitPost(_ node: CatchClauseSyntax) { result += 1 }
        override func visitPost(_ node: SwitchCaseSyntax) { result += 1 }
        override func visitPost(_ node: BinaryOperatorExprSyntax) {
            let op = node.operator.text
            if op == "&&" || op == "||" { result += 1 }
        }
        override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind { .skipChildren }
        override func visit(_ node: InitializerDeclSyntax) -> SyntaxVisitorContinueKind { .skipChildren }
    }
    let visitor = Visitor(viewMode: .sourceAccurate)
    visitor.walk(body)
    return visitor.result
}

nonisolated func cognitive(of function: WithOptionalCodeBlockSyntax) -> Int {
    guard let body = function.body else { return 0 }
    final class Visitor: SyntaxVisitor {
        var result = 0
        var depth = 0
        override func visit(_ node: ForStmtSyntax) -> SyntaxVisitorContinueKind {
            result += 1 + depth
            depth += 1
            return .visitChildren
        }
        override func visitPost(_ node: ForStmtSyntax) {
            depth -= 1
        }
        override func visit(_ node: WhileStmtSyntax) -> SyntaxVisitorContinueKind {
            result += 1 + depth
            depth += 1
            return .visitChildren
        }
        override func visitPost(_ node: WhileStmtSyntax) {
            depth -= 1
        }
        override func visit(_ node: RepeatStmtSyntax) -> SyntaxVisitorContinueKind {
            result += 1 + depth
            depth += 1
            return .visitChildren
        }
        override func visitPost(_ node: RepeatStmtSyntax) {
            depth -= 1
        }
        override func visit(_ node: IfExprSyntax) -> SyntaxVisitorContinueKind {
            result += 1 + depth
            depth += 1
            return .visitChildren
        }
        override func visitPost(_ node: IfExprSyntax) {
            depth -= 1
        }
        override func visit(_ node: SwitchExprSyntax) -> SyntaxVisitorContinueKind {
            result += 1 + depth
            depth += 1
            return .visitChildren
        }
        override func visitPost(_ node: SwitchExprSyntax) {
            depth -= 1
        }
        override func visit(_ node: GuardStmtSyntax) -> SyntaxVisitorContinueKind {
            // guard does not increase nesting so no depth penalty
            result += 1
            return .visitChildren
        }
        override func visit(_ node: CatchClauseSyntax) -> SyntaxVisitorContinueKind {
            result += 1 + depth
            depth += 1
            return .visitChildren
        }
        override func visitPost(_ node: CatchClauseSyntax) {
            depth -= 1
        }
        // && and || increment but don't nest
        override func visitPost(_ node: BinaryOperatorExprSyntax) {
            let op = node.operator.text
            if op == "&&" || op == "||" { result += 1 }
        }
        // ! does the same
        override func visitPost(_ node: PrefixOperatorExprSyntax) {
            if node.operator.text == "!" { result += 1 }
        }

        // nested function reset depth tracking
        override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind { .skipChildren }
        override func visit(_ node: InitializerDeclSyntax) -> SyntaxVisitorContinueKind { .skipChildren }
    }
    let visitor = Visitor(viewMode: .sourceAccurate)
    visitor.walk(body)
    return visitor.result
}

nonisolated func nestingDepth(of function: WithOptionalCodeBlockSyntax) -> Int {
    guard let body = function.body else { return 0 }
    final class Visitor: SyntaxVisitor {
        var current = 0
        var max = 0

        private func enter() {
            current += 1
            if current > max { max = current }
        }
        private func exit() { current -= 1 }

        override func visit(_ node: ForStmtSyntax) -> SyntaxVisitorContinueKind { enter(); return .visitChildren }
        override func visitPost(_ node: ForStmtSyntax) { exit() }

        override func visit(_ node: WhileStmtSyntax) -> SyntaxVisitorContinueKind { enter(); return .visitChildren }
        override func visitPost(_ node: WhileStmtSyntax) { exit() }

        override func visit(_ node: RepeatStmtSyntax) -> SyntaxVisitorContinueKind { enter(); return .visitChildren }
        override func visitPost(_ node: RepeatStmtSyntax) { exit() }

        override func visit(_ node: IfExprSyntax) -> SyntaxVisitorContinueKind { enter(); return .visitChildren }
        override func visitPost(_ node: IfExprSyntax) { exit() }

        override func visit(_ node: SwitchExprSyntax) -> SyntaxVisitorContinueKind { enter(); return .visitChildren }
        override func visitPost(_ node: SwitchExprSyntax) { exit() }

        override func visit(_ node: GuardStmtSyntax) -> SyntaxVisitorContinueKind { enter(); return .visitChildren }
        override func visitPost(_ node: GuardStmtSyntax) { exit() }

        override func visit(_ node: CatchClauseSyntax) -> SyntaxVisitorContinueKind { enter(); return .visitChildren }
        override func visitPost(_ node: CatchClauseSyntax) { exit() }

        override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind { .skipChildren }
        override func visit(_ node: InitializerDeclSyntax) -> SyntaxVisitorContinueKind { .skipChildren }

    }
    let visitor = Visitor(viewMode: .sourceAccurate)
    visitor.walk(body)
    return visitor.max
}

nonisolated func parameterCount(of function: FunctionDeclSyntax) -> Int {
    function.signature.parameterClause.parameters.count
}

nonisolated func parameterCount(of initializer: InitializerDeclSyntax) -> Int {
    initializer.signature.parameterClause.parameters.count
}
