import AppKit
import QuickLookThumbnailing

/// The Finder icon of an EPUB: its cover. Books without a cover keep the system's generic icon.
final class ThumbnailProvider: QLThumbnailProvider {
    override func provideThumbnail(for request: QLFileThumbnailRequest, _ handler: @escaping (QLThumbnailReply?, Error?) -> Void) {
        do {
            let book = try Book(url: request.fileURL, mapped: true)
            guard let cover = book.cover, let image = NSImage(data: try book.resource(at: cover).data),
                  image.size.width > 0, image.size.height > 0
            else { return handler(nil, CocoaError(.fileReadCorruptFile)) }

            let box = request.maximumSize
            let scale = min(box.width / image.size.width, box.height / image.size.height)
            let size = CGSize(width: (image.size.width * scale).rounded(), height: (image.size.height * scale).rounded())
            handler(QLThumbnailReply(contextSize: size, currentContextDrawing: {
                image.draw(in: CGRect(origin: .zero, size: size))
                return true
            }), nil)
        } catch {
            handler(nil, error)
        }
    }
}
