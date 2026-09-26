import Foundation

enum XcodeXMLError: Error, Equatable, Sendable {
    case invalidDocument
}

struct XcodeXMLNode {
    let name: String
    let attributes: [String: String]
    let children: [XcodeXMLNode]
}

enum XcodeXML {
    static func parse(_ data: Data, maximumBytes: Int) throws(XcodeXMLError) -> XcodeXMLNode {
        guard data.count <= maximumBytes,
            let source = String(data: data, encoding: .utf8) else {
            throw .invalidDocument
        }
        let processingInstructions = source.components(separatedBy: "<?").count
        guard !source.contains("<!"),
            processingInstructions == 1
                || (processingInstructions == 2 && source.hasPrefix("<?xml ")) else {
            throw .invalidDocument
        }
        let parser = XMLParser(data: data)
        parser.shouldResolveExternalEntities = false
        let collector = XcodeXMLCollector()
        parser.delegate = collector
        guard parser.parse(), !collector.invalid,
            let root = collector.root else {
            throw .invalidDocument
        }
        return root
    }
}

private final class XcodeXMLCollector: NSObject, XMLParserDelegate {
    private struct Frame {
        let name: String
        let attributes: [String: String]
        var children: [XcodeXMLNode] = []
    }

    private var frames: [Frame] = []
    private var nodeCount = 0
    private(set) var root: XcodeXMLNode?
    private(set) var invalid = false

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String]
    ) {
        guard !invalid, frames.count < 32, nodeCount < 4_096,
            root == nil || !frames.isEmpty else {
            invalid = true
            return
        }
        nodeCount += 1
        frames.append(Frame(name: elementName, attributes: attributeDict))
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        guard !invalid, let frame = frames.popLast(), frame.name == elementName else {
            invalid = true
            return
        }
        let node = XcodeXMLNode(
            name: frame.name,
            attributes: frame.attributes,
            children: frame.children
        )
        if frames.isEmpty {
            guard root == nil else {
                invalid = true
                return
            }
            root = node
        } else {
            frames[frames.count - 1].children.append(node)
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if !string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            invalid = true
        }
    }
}
