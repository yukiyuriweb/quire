import Foundation

/// One entry of the table of contents. A class, because `NSOutlineView` identifies items by reference.
final class TOCItem: NSObject {
    let title: String
    let url: URL?
    let children: [TOCItem]
    weak var parent: TOCItem?

    init(title: String, url: URL?, children: [TOCItem]) {
        self.title = title
        self.url = url
        self.children = children
        super.init()
        children.forEach { $0.parent = self }
    }
}

/// An opened EPUB: its title, reading order and table of contents, and access to its files.
///
/// Files are addressed by `quire://book/<path in archive>` URLs, served to the web view by
/// `BookSchemeHandler`, so relative links, images and stylesheets resolve as they do in the archive.
final class Book {
    static let scheme = "quire"
    static let root = URL(string: "quire://book/")!

    enum BookError: LocalizedError {
        case notEPUB, drm

        var errorDescription: String? {
            switch self {
            case .notEPUB: String(localized: "The file isn't a valid EPUB.")
            case .drm: String(localized: "The book is protected by DRM and can't be opened.")
            }
        }
    }

    let title: String
    let authors: [String]
    /// The cover image, if the package names one.
    let cover: URL?
    /// The documents in reading order (the linear items of the spine).
    let spine: [URL]
    let toc: [TOCItem]
    private let archive: ZipArchive
    private let mediaTypes: [String: String]

    /// `mapped` is for the short-lived Quick Look extensions; see `ZipArchive.init`.
    init(url: URL, mapped: Bool = false) throws {
        archive = try ZipArchive(url: url, mapped: mapped)
        try Self.checkEncryption(archive)

        guard let container = try? Self.xml(archive.read("META-INF/container.xml")),
              let rootfile = Self.elements(container, "rootfile").first,
              let opfPath = Self.attr(rootfile, "full-path"),
              let opf = try? Self.xml(archive.read(opfPath))
        else { throw BookError.notEPUB }
        let opfURL = Self.url(forEntry: opfPath)

        var manifest: [String: (url: URL, type: String, properties: String)] = [:]
        var types: [String: String] = [:]
        for item in Self.elements(opf, "item") {
            guard let id = Self.attr(item, "id"), let href = Self.attr(item, "href"),
                  let url = Self.resolve(href, against: opfURL) else { continue }
            let type = Self.attr(item, "media-type") ?? ""
            manifest[id] = (url, type, Self.attr(item, "properties") ?? "")
            if let path = Self.entryPath(url) { types[path] = type }
        }
        mediaTypes = types

        let itemrefs = Self.elements(opf, "itemref").filter { Self.attr($0, "linear") != "no" }
        spine = itemrefs.compactMap { Self.attr($0, "idref").flatMap { manifest[$0]?.url } }
        guard !spine.isEmpty else { throw BookError.notEPUB }

        let titles = Self.elements(opf, "title").map { Self.text($0) }.filter { !$0.isEmpty }
        title = titles.first ?? url.deletingPathExtension().lastPathComponent
        authors = Self.elements(opf, "creator").map { Self.text($0) }.filter { !$0.isEmpty }

        // EPUB 3 marks the cover item; EPUB 2 names it in <meta name="cover" content="id">
        // (some books put the href there instead). Failing both, an image called "cover".
        let images = manifest.filter { $0.value.type.hasPrefix("image/") }
        let coverMeta = Self.elements(opf, "meta").first { Self.attr($0, "name") == "cover" }.flatMap { Self.attr($0, "content") }
        cover = images.values.first { $0.properties.split(separator: " ").contains("cover-image") }?.url
            ?? coverMeta.flatMap { images[$0]?.url ?? Self.resolve($0, against: opfURL) }.flatMap { url in
                images.values.contains { $0.url == url } ? url : nil
            }
            ?? images.sorted { $0.key < $1.key }.first { $0.key.lowercased().contains("cover") || $0.value.url.lastPathComponent.lowercased().contains("cover") }?.value.url

        var toc: [TOCItem] = []
        // EPUB 3 navigation document first, then the EPUB 2 NCX, then the bare reading order.
        if let nav = manifest.values.first(where: { $0.properties.split(separator: " ").contains("nav") }) {
            toc = (try? Self.navTOC(archive, nav.url)) ?? []
        }
        if toc.isEmpty {
            let ncxID = Self.elements(opf, "spine").first.flatMap { Self.attr($0, "toc") }
            if let ncx = ncxID.flatMap({ manifest[$0] }) ?? manifest.values.first(where: { $0.type == "application/x-dtbncx+xml" }) {
                toc = (try? Self.ncxTOC(archive, ncx.url)) ?? []
            }
        }
        if toc.isEmpty {
            toc = spine.map { TOCItem(title: $0.deletingPathExtension().lastPathComponent, url: $0, children: []) }
        }
        self.toc = toc
    }

    /// The file at a `quire://book/` URL, with its MIME type.
    func resource(at url: URL) throws -> (data: Data, mimeType: String) {
        guard let path = Self.entryPath(url) else { throw CocoaError(.fileReadNoSuchFile) }
        let data = try archive.read(path)
        let type = mediaTypes[path].flatMap { $0.isEmpty ? nil : $0 } ?? Self.mimeType(forExtension: (path as NSString).pathExtension)
        return (data, type)
    }

    // MARK: - URLs

    static func url(forEntry path: String) -> URL { root.appendingPathComponent(path) }

    static func entryPath(_ url: URL) -> String? {
        guard url.scheme == scheme else { return nil }
        return String(url.path.dropFirst())
    }

    static func resolve(_ href: String, against base: URL) -> URL? {
        var allowed = CharacterSet.urlPathAllowed
        allowed.insert("#")
        let url = URL(string: href, relativeTo: base)
            ?? href.addingPercentEncoding(withAllowedCharacters: allowed).flatMap { URL(string: $0, relativeTo: base) }
        return url?.absoluteURL.standardized
    }

    private static func mimeType(forExtension ext: String) -> String {
        switch ext.lowercased() {
        case "xhtml", "xht": "application/xhtml+xml"
        case "html", "htm": "text/html"
        case "css": "text/css"
        case "svg": "image/svg+xml"
        case "png": "image/png"
        case "jpg", "jpeg": "image/jpeg"
        case "gif": "image/gif"
        case "webp": "image/webp"
        case "otf": "font/otf"
        case "ttf": "font/ttf"
        case "woff": "font/woff"
        case "woff2": "font/woff2"
        default: "application/octet-stream"
        }
    }

    // MARK: - Parsing

    /// Font obfuscation is harmless (we only lose the embedded font); any other encryption is DRM.
    private static func checkEncryption(_ archive: ZipArchive) throws {
        guard archive.contains("META-INF/encryption.xml") else { return }
        let fontObfuscation: Set = ["http://www.idpf.org/2008/embedding", "http://ns.adobe.com/pdf/enc#RC"]
        let doc = try xml(archive.read("META-INF/encryption.xml"))
        for method in elements(doc, "EncryptionMethod") where !fontObfuscation.contains(attr(method, "Algorithm") ?? "") {
            throw BookError.drm
        }
    }

    private static func navTOC(_ archive: ZipArchive, _ url: URL) throws -> [TOCItem] {
        guard let path = entryPath(url) else { return [] }
        let doc = try xml(archive.read(path))
        let navs = elements(doc, "nav")
        guard let nav = navs.first(where: { (attr($0, "type") ?? "").split(separator: " ").contains("toc") }) ?? navs.first,
              let list = children(nav, "ol").first else { return [] }

        func items(_ ol: XMLElement) -> [TOCItem] {
            children(ol, "li").compactMap { li in
                let label = children(li, "a").first ?? children(li, "span").first
                let title = label.map(text) ?? ""
                let sub = children(li, "ol").first.map(items) ?? []
                if title.isEmpty && sub.isEmpty { return nil }
                let href = label.flatMap { attr($0, "href") }
                return TOCItem(title: title, url: href.flatMap { resolve($0, against: url) }, children: sub)
            }
        }
        return items(list)
    }

    private static func ncxTOC(_ archive: ZipArchive, _ url: URL) throws -> [TOCItem] {
        guard let path = entryPath(url) else { return [] }
        let doc = try xml(archive.read(path))
        guard let map = elements(doc, "navMap").first else { return [] }

        func items(_ parent: XMLElement) -> [TOCItem] {
            children(parent, "navPoint").map { point in
                let label = children(point, "navLabel").first.flatMap { children($0, "text").first }
                let src = children(point, "content").first.flatMap { attr($0, "src") }
                return TOCItem(title: label.map(text) ?? "", url: src.flatMap { resolve($0, against: url) }, children: items(point))
            }
        }
        return items(map)
    }

    // MARK: - SVG

    private static let colorPattern = try! NSRegularExpression(
        pattern: #"(?:fill|stroke|stop-color|flood-color|color)\s*[:=]\s*["']?\s*([^;"'}>]+)"#, options: [.caseInsensitive])
    private static let rgbPattern = try! NSRegularExpression(pattern: #"^rgba?\(\s*([\d.]+)(%?)\s*,\s*([\d.]+)%?\s*,\s*([\d.]+)%?"#)

    /// No embedded raster image, and every colour it names is black, white, grey or the text colour:
    /// e.g. an equation converted from a PDF. Dark mode inverts these rather than putting them on white.
    static func isInkOnlySVG(_ svg: String) -> Bool {
        if svg.contains("<image") { return false }
        let range = NSRange(svg.startIndex..., in: svg)
        return colorPattern.matches(in: svg, range: range).allSatisfy { match in
            isAchromatic(String(svg[Range(match.range(at: 1), in: svg)!]).trimmingCharacters(in: .whitespaces).lowercased())
        }
    }

    private static func isAchromatic(_ color: String) -> Bool {
        let named: Set = ["none", "currentcolor", "inherit", "transparent", "black", "white", "gray", "grey", "silver"]
        if named.contains(color) || color.hasPrefix("url(") { return true }
        var channels: [Double] = []
        if color.hasPrefix("#") {
            var hex = String(color.dropFirst().prefix(6))
            if hex.count == 3 { hex = hex.map { "\($0)\($0)" }.joined() }
            guard hex.count == 6, let value = Int(hex, radix: 16) else { return false }
            channels = [value >> 16 & 0xff, value >> 8 & 0xff, value & 0xff].map { Double($0) / 255 }
        } else if let match = rgbPattern.firstMatch(in: color, range: NSRange(color.startIndex..., in: color)) {
            let scale = color[Range(match.range(at: 2), in: color)!] == "%" ? 100.0 : 255.0
            channels = [1, 3, 4].compactMap { Double(color[Range(match.range(at: $0), in: color)!]).map { $0 / scale } }
        }
        guard channels.count == 3 else { return false }
        return channels.max()! - channels.min()! < 0.05
    }

    // MARK: - XML helpers (namespace prefixes are ignored; elements and attributes match by local name)

    private static func xml(_ data: Data) throws -> XMLDocument {
        do {
            return try XMLDocument(data: data)
        } catch {
            // Tolerate sloppy documents, e.g. HTML entities such as &nbsp; in a navigation document.
            return try XMLDocument(data: data, options: .documentTidyXML)
        }
    }

    private static func elements(_ doc: XMLDocument, _ name: String) -> [XMLElement] {
        (try? doc.nodes(forXPath: "//*[local-name()='\(name)']"))?.compactMap { $0 as? XMLElement } ?? []
    }

    private static func children(_ element: XMLElement, _ name: String) -> [XMLElement] {
        (element.children ?? []).compactMap { $0 as? XMLElement }.filter { $0.localName == name }
    }

    private static func attr(_ element: XMLElement, _ name: String) -> String? {
        element.attributes?.first { $0.localName == name }?.stringValue
    }

    /// Text content with runs of whitespace collapsed, as it would be displayed.
    private static func text(_ element: XMLElement) -> String {
        (element.stringValue ?? "").split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}
