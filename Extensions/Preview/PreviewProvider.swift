import Quartz
import UniformTypeIdentifiers

/// The Quick Look preview (Space in Finder): cover, title, authors and the first ten or so pages, as HTML.
final class PreviewProvider: QLPreviewProvider, QLPreviewingController {
    func providePreview(for request: QLFilePreviewRequest) async throws -> QLPreviewReply {
        let book = try Book(url: request.fileURL, mapped: true)
        let cover = book.cover.flatMap { try? book.resource(at: $0) }
        let excerpt = Excerpt(book: book)
        var files = excerpt.attachments
        if let cover { files["cover"] = cover }
        let html = PreviewPage.html(for: book, coverSource: cover == nil ? nil : "cid:cover", excerpt: excerpt)
        return QLPreviewReply(dataOfContentType: .html, contentSize: CGSize(width: 800, height: 720)) { reply in
            reply.stringEncoding = .utf8
            reply.attachments = files.mapValues {
                QLPreviewReplyAttachment(data: $0.data, contentType: UTType(mimeType: $0.mimeType) ?? .data)
            }
            return Data(html.utf8)
        }
    }
}
