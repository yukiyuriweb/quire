import AppKit

/// An EPUB file, opened read-only. Named `Document` for Objective-C so Info.plist can refer to it.
@objc(Document)
final class Document: NSDocument {
    private var book: Book?

    override class var autosavesInPlace: Bool { false }

    override func read(from url: URL, ofType typeName: String) throws {
        book = try Book(url: url)
    }

    override func makeWindowControllers() {
        guard let book, let url = fileURL else { return }
        // NFC, so the same file gets the same key whether its path came from Finder or a terminal.
        addWindowController(BookWindowController(book: book, positionKey: url.standardizedFileURL.path.precomposedStringWithCanonicalMapping))
    }
}
