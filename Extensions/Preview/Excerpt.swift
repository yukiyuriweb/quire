import Foundation

/// The opening of a book, about ten pages, as HTML for the Quick Look preview.
///
/// Documents are taken in reading order, block by block, until the budget is used. A block that
/// would overflow is still taken whole if it is a paragraph, or entered if it is a container such as
/// a `<section>`, so the excerpt ends at a paragraph boundary. The book's stylesheets are dropped (the
/// preview has its own), images become attachments referenced as `cid:`, and links are made inert.
final class Excerpt {
    /// About ten pages: 6000 Japanese characters or 3000 English words (each word counts 2).
    static let budget = 6000
    private static let imageWeight = 150
    /// A document with images but no text is a page of a fixed-layout book.
    private static let pageWeight = 600
    private static let maxAttachmentBytes = 16 << 20
    private static let containers: Set = ["body", "section", "div", "article", "main"]
    private static let dropped: Set = ["script", "style", "link", "meta", "object", "embed", "iframe", "video", "audio"]

    private(set) var html = ""
    private(set) var attachments: [String: (data: Data, mimeType: String)] = [:]
    /// Whether the book goes on past the excerpt.
    private(set) var truncated = false

    private let book: Book
    private var used = 0
    private var bytes = 0
    private var names: [URL: String] = [:]
    private var isFull: Bool { used >= Self.budget || bytes >= Self.maxAttachmentBytes }

    init(book: Book) {
        self.book = book
        var parts: [String] = []
        for (index, url) in book.spine.enumerated() {
            if isFull { truncated = true; break }
            guard let data = try? book.resource(at: url).data, let doc = Self.parse(data),
                  let body = Self.elements(doc.rootElement()).first(where: { $0.localName == "body" }) else { continue }
            let hasText = Self.units(body.stringValue ?? "") > 0
            let images = Self.elements(body).filter { $0.localName == "img" || $0.localName == "image" }
            // The cover page: the cover is already shown above the excerpt.
            if index == 0, !hasText, let cover = book.cover,
               images.contains(where: { Self.source($0).flatMap { Book.resolve($0, against: url) } == cover }) { continue }

            let section = XMLElement(name: "section")
            take(body, base: url, into: section)
            if !hasText && !images.isEmpty { used += max(0, Self.pageWeight - Self.imageWeight * images.count) }
            parts.append(Self.serialize(section))
        }
        html = parts.joined(separator: "\n")
    }

    /// Copies `node`'s children into `out` until the budget runs out. Returns false once it has.
    @discardableResult
    private func take(_ node: XMLElement, base: URL, into out: XMLElement) -> Bool {
        for child in node.children ?? [] {
            if isFull { truncated = true; return false }
            let weight = Self.weight(child)
            if used + weight > Self.budget, let element = child as? XMLElement,
               Self.containers.contains(element.localName ?? ""), Self.elements(element).count > 1 {
                let shell = XMLElement(name: element.localName ?? "div")
                element.attributes?.filter { $0.localName != "style" }.forEach { shell.addAttribute($0.copy() as! XMLNode) }
                out.addChild(shell)
                if !take(element, base: base, into: shell) { return false }
                continue
            }
            guard let copy = clean(child, base: base) else { continue }
            out.addChild(copy)
            used += weight
        }
        return true
    }

    /// A copy of `node` without scripts, styles or live links, its images pointing to attachments.
    /// Inline styles go too (a `color: black` would be unreadable in dark mode), except inside an
    /// `<svg>`, whose drawing may depend on them.
    private func clean(_ node: XMLNode, base: URL) -> XMLNode? {
        if node.kind == .comment || node.kind == .processingInstruction { return nil }
        let copy = node.copy() as! XMLNode
        guard let root = copy as? XMLElement else { return copy }
        if Self.dropped.contains(root.localName ?? "") { return nil }
        for element in [root] + Self.elements(root) {
            for child in element.children ?? [] where Self.dropped.contains(child.localName ?? "") { child.detach() }
            if !sequence(first: element as XMLNode, next: \.parent).contains(where: { $0.localName == "svg" }) {
                element.attributes?.filter { $0.localName == "style" }.forEach { element.removeAttribute(forName: $0.name ?? "") }
            }
            switch element.localName {
            case "a":
                element.removeAttribute(forName: "href")
            case "img", "image":
                element.attributes?.filter { $0.localName == "srcset" }.forEach { element.removeAttribute(forName: $0.name ?? "") }
                guard let attribute = element.attributes?.first(where: { $0.localName == "src" || $0.localName == "href" }),
                      let src = attribute.stringValue, let url = Book.resolve(src, against: base),
                      let name = attach(url) else { continue }
                attribute.stringValue = "cid:\(name)"
                if attachments[name]?.mimeType == "image/svg+xml",
                   let data = attachments[name]?.data, Book.isInkOnlySVG(String(decoding: data, as: UTF8.self)) {
                    let classes = element.attribute(forName: "class")?.stringValue ?? ""
                    element.addAttribute(XMLNode.attribute(withName: "class", stringValue: classes + " quire-ink") as! XMLNode)
                }
            default:
                break
            }
        }
        return root
    }

    private func attach(_ url: URL) -> String? {
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.fragment = nil
        let key = components?.url ?? url
        if let name = names[key] { return name }
        guard bytes < Self.maxAttachmentBytes, let resource = try? book.resource(at: key) else { return nil }
        let name = "image\(names.count)"
        names[key] = name
        attachments[name] = resource
        bytes += resource.data.count
        return name
    }

    // MARK: - Helpers

    /// How much of the budget a node uses: its text, plus a share for each image.
    private static func weight(_ node: XMLNode) -> Int {
        let images = (node as? XMLElement).map { [$0] + elements($0) }?.filter { $0.localName == "img" || $0.localName == "image" }.count ?? 0
        return units(node.stringValue ?? "") + imageWeight * images
    }

    /// Japanese characters count 1 each; a word in a language written with spaces counts 2.
    static func units(_ text: String) -> Int {
        text.split(whereSeparator: \.isWhitespace).reduce(0) { total, token in
            let cjk = token.unicodeScalars.filter {
                (0x3000...0x30FF).contains($0.value) || (0x3400...0x9FFF).contains($0.value)
                    || (0xF900...0xFAFF).contains($0.value) || (0xFF00...0xFFEF).contains($0.value)
            }.count
            return total + (cjk > 0 ? cjk : 2)
        }
    }

    private static func source(_ element: XMLElement) -> String? {
        element.attributes?.first { $0.localName == "src" || $0.localName == "href" }?.stringValue
    }

    /// All descendant elements, depth first.
    private static func elements(_ node: XMLNode?) -> [XMLElement] {
        (node?.children ?? []).flatMap { child -> [XMLElement] in
            guard let element = child as? XMLElement else { return [] }
            return [element] + elements(element)
        }
    }

    private static func parse(_ data: Data) -> XMLDocument? {
        (try? XMLDocument(data: data)) ?? (try? XMLDocument(data: data, options: .documentTidyXML))
    }

    private static let voidEndTags = try! NSRegularExpression(
        pattern: "</(?:area|base|br|col|embed|hr|img|input|source|track|wbr)>", options: [.caseInsensitive])

    /// The preview is parsed as HTML, where `<span/>` would swallow what follows: write every element
    /// with an end tag, then drop the end tags HTML doesn't allow (`</br>` would be a second break).
    private static func serialize(_ element: XMLElement) -> String {
        let xml = element.xmlString(options: [.nodeExpandEmptyElement])
        return voidEndTags.stringByReplacingMatches(in: xml, range: NSRange(xml.startIndex..., in: xml), withTemplate: "")
    }
}
