import Foundation

/// Builds the preview page. Kept apart from `PreviewProvider` so it can be tested without Quick Look.
enum PreviewPage {
    /// Cover, title and authors, then the opening of the book in Quire's own style (the book's CSS
    /// is dropped, and Quick Look runs no JavaScript, so this is what keeps dark mode readable).
    static func html(for book: Book, coverSource: String?, excerpt: Excerpt) -> String {
        let cover = coverSource.map { "<div class=\"cover\"><img src=\"\(escape($0))\" alt=\"\"></div>" } ?? ""
        let authors = book.authors.isEmpty ? "" : "<p class=\"authors\">\(escape(book.authors.joined(separator: ", ")))</p>"
        let more = excerpt.truncated ? "<p class=\"more\">\(escape(String(localized: "Continue reading in Quire.")))</p>" : ""
        return """
        <!DOCTYPE html>
        <html><head><meta charset="utf-8"><style>
        :root { color-scheme: light dark; }
        body { margin: 0; padding: 28px 36px 40px; font: 15px/1.8 "Hiragino Mincho ProN", "YuMincho", Georgia, serif; }
        header, article { max-width: 42em; margin: 0 auto; }
        header { display: flex; gap: 24px; align-items: flex-end; margin-bottom: 28px; padding-bottom: 24px;
                 border-bottom: 1px solid rgba(127, 127, 127, .3); font-family: -apple-system, "Hiragino Sans", sans-serif; }
        .cover { flex: 0 0 120px; }
        .cover img { display: block; width: 100%; border-radius: 3px; box-shadow: 0 2px 10px rgba(0, 0, 0, .3); }
        h1.title { font-size: 22px; line-height: 1.3; margin: 0 0 6px; }
        .authors { color: GrayText; font-size: 14px; margin: 0; }
        article h1, article h2, article h3, article h4 { font-family: -apple-system, "Hiragino Sans", sans-serif; line-height: 1.4; }
        article img, article svg, article video { max-width: 100%; height: auto; }
        article a { color: inherit; text-decoration: none; }
        pre, code, kbd, samp { font-family: ui-monospace, Menlo, monospace; }
        pre { white-space: pre-wrap; font-size: 13px; line-height: 1.5; padding: .8em 1em; border-radius: 6px; background: rgba(127, 127, 127, .12); }
        :not(pre) > code, kbd { font-size: .88em; padding: .1em .3em; border-radius: 3px; background: rgba(127, 127, 127, .15); }
        table { border-collapse: collapse; }
        th, td { padding: .3em .6em; border-bottom: 1px solid rgba(127, 127, 127, .35); }
        blockquote { margin-left: 0; padding-left: 1em; border-left: 3px solid rgba(127, 127, 127, .4); }
        .more { margin-top: 2.5em; text-align: center; color: GrayText; font: 13px -apple-system, "Hiragino Sans", sans-serif; }
        @media (prefers-color-scheme: dark) {
          /* As in the app: dark drawings get a white background, except SVG in the text colour
             (MathJax) and black-and-grey SVG images, which are inverted instead. */
          article img:not(.quire-ink), article :not(svg) > svg:not(:has([fill="currentColor" i], [stroke="currentColor" i])) { background: #fff; }
          article img.quire-ink { filter: invert(.86); }
        }
        </style></head><body>
        <header>\(cover)<div><h1 class="title">\(escape(book.title))</h1>\(authors)</div></header>
        <article>
        \(excerpt.html)
        </article>
        \(more)
        </body></html>
        """
    }

    private static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
    }
}
