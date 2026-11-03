import AppKit
import WebKit

/// Serves the book's files to the web view under `quire://book/`.
final class BookSchemeHandler: NSObject, WKURLSchemeHandler {
    private let book: Book
    /// SVG images served so far that are drawn in black and grey only, e.g. equations converted from
    /// a PDF. In dark mode they are inverted rather than put on a white background.
    private(set) var inkOnlyImages: Set<String> = []

    init(book: Book) { self.book = book }

    func webView(_ webView: WKWebView, start task: WKURLSchemeTask) {
        guard let url = task.request.url else { return }
        do {
            let (data, mimeType) = try book.resource(at: url)
            if mimeType == "image/svg+xml", Book.isInkOnlySVG(String(decoding: data, as: UTF8.self)) {
                inkOnlyImages.insert(url.absoluteString)
            }
            task.didReceive(URLResponse(url: url, mimeType: mimeType, expectedContentLength: data.count, textEncodingName: nil))
            task.didReceive(data)
            task.didFinish()
        } catch {
            task.didFailWithError(error)
        }
    }

    func webView(_ webView: WKWebView, stop task: WKURLSchemeTask) {}
}

/// Lets the window controller handle chapter keys before the web view scrolls.
final class ReaderView: WKWebView {
    var onKeyDown: ((NSEvent) -> Bool)?

    override func keyDown(with event: NSEvent) {
        if onKeyDown?(event) != true { super.keyDown(with: event) }
    }
}

/// `WKUserContentController` retains its handlers; this keeps it from retaining the window controller.
private final class WeakMessageHandler: NSObject, WKScriptMessageHandler {
    weak var target: WKScriptMessageHandler?

    init(_ target: WKScriptMessageHandler) { self.target = target }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        target?.userContentController(controller, didReceive: message)
    }
}

extension Notification.Name {
    static let pageZoomChanged = Notification.Name("QuirePageZoomChanged")
}

final class BookWindowController: NSWindowController, NSWindowDelegate, NSOutlineViewDataSource, NSOutlineViewDelegate,
    WKNavigationDelegate, WKScriptMessageHandler, NSToolbarDelegate, NSMenuItemValidation, NSToolbarItemValidation {
    private let book: Book
    /// Where the reading position is stored: the file's path.
    private let positionKey: String
    private let webView: ReaderView
    private let schemeHandler: BookSchemeHandler
    private let outline = NSOutlineView()

    private var chapter = 0
    private var fraction = 0.0
    private var atTop = true
    private var atBottom = true
    /// Scroll position (0...1) to apply once the page being loaded finishes.
    private var pendingFraction: Double?
    /// Set while the outline's selection is changed in code, so it doesn't count as a click.
    private var syncingSelection = false

    /// Applied to every page: a readable measure (in px, since some books set `font-size: 0` on the root), dark mode, and reporting of the scroll position.
    /// Runs in the app's own script world, so it works with the book's JavaScript turned off.
    private static let userScript = """
    (() => {
      const style = document.createElement('style');
      style.textContent = `
        :root { color-scheme: light dark; }
        html { padding: 24px 48px 64px; }
        body { max-width: 720px !important; margin-left: auto !important; margin-right: auto !important; }
        img, svg, video { max-width: 100%; height: auto; }
        @media (prefers-color-scheme: dark) {
          html { background: #1e1e1e; color: #dcdcdc; }
          /* Hidden until the book's own colours have been darkened (see darken below). */
          html:not(.quire-ready) body { visibility: hidden !important; }
          /* Images may be dark drawings on a transparent background: give them a white one, except
             SVG drawn in the text colour (e.g. MathJax), which follows dark mode by itself, and
             black-and-grey SVG images (.quire-ink), inverted to match the text instead. */
          img:not(.quire-ink), :not(svg) > svg:not(:has([fill="currentColor" i], [stroke="currentColor" i])) { background: #fff; }
          img.quire-ink { filter: invert(0.86); }
        }`;
      (document.head || document.documentElement).prepend(style);

      // Dark mode for books whose CSS sets its own colours (code blocks, tables, quotes, headings):
      // flip the lightness of every colour the page actually uses, keeping its hue. Light
      // backgrounds become dark, dark text and accents become light. Images are left alone.
      const dark = matchMedia('(prefers-color-scheme: dark)');
      const changed = [];  // [element, property, previous inline value, previous priority]
      const parse = (color) => {
        if (!color.startsWith('rgb')) return null;
        const p = color.slice(color.indexOf('(') + 1, color.lastIndexOf(')')).split(/[ ,/]+/).filter(Boolean).map(parseFloat);
        return p.length >= 3 ? [p[0] / 255, p[1] / 255, p[2] / 255, p.length > 3 ? p[3] : 1] : null;
      };
      const remap = (color, lightness) => {
        const c = parse(color);
        if (!c || c[3] === 0) return null;
        const [r, g, b] = c, max = Math.max(r, g, b), min = Math.min(r, g, b), l = (max + min) / 2, d = max - min;
        const to = lightness(l);
        if (to === null) return null;
        // Keep the chroma (d), not the HSL saturation: an off-white paper colour has a high
        // saturation, and keeping that would turn it into a strong brown when darkened.
        const h = d === 0 ? 0 : max === r ? ((g - b) / d + 6) % 6 : max === g ? (b - r) / d + 2 : (r - g) / d + 4;
        const k = (n) => (n + h * 2) % 12, a = Math.min(d / 2, to, 1 - to);
        const f = (n) => Math.round(255 * (to - a * Math.max(-1, Math.min(k(n) - 3, 9 - k(n), 1))));
        return `rgba(${f(0)}, ${f(8)}, ${f(4)}, ${c[3]})`;
      };
      const text = (l) => l < 0.6 ? Math.max(1 - l, 0.6) : null;
      const background = (l) => l > 0.4 ? 0.12 + (1 - l) * 0.3 : null;
      const rule = (l) => Math.min(Math.max(1 - l, 0.25), 0.75);
      const darken = () => {
        const html = 'http://www.w3.org/1999/xhtml', skip = new Set(['IMG', 'VIDEO', 'CANVAS', 'IFRAME']);
        const plan = [], pseudoRules = [];
        const add = (el, property, value) => { if (value) plan.push([el, property, value]); };
        for (const el of [document.documentElement, ...document.documentElement.querySelectorAll('body, body *')]) {
          if (el.namespaceURI !== html || skip.has(el.tagName.toUpperCase())) continue;  // SVG, MathML, images
          const cs = getComputedStyle(el);
          // Every element, even if its colour equals its parent's: a rule may set the same colour
          // on it, and then it wouldn't inherit the parent's new one.
          add(el, 'color', remap(cs.color, text));
          add(el, 'background-color', remap(cs.backgroundColor, background));
          for (const side of ['top', 'right', 'bottom', 'left']) {
            if (cs.getPropertyValue(`border-${side}-style`) !== 'none' && parseFloat(cs.getPropertyValue(`border-${side}-width`)) > 0)
              add(el, `border-${side}-color`, remap(cs.getPropertyValue(`border-${side}-color`), rule));
          }
          // ::before / ::after can't take inline styles; they get rules in a stylesheet instead.
          for (const pseudo of ['::before', '::after']) {
            const ps = getComputedStyle(el, pseudo);
            if (ps.content === 'none' || ps.content === 'normal') continue;
            const color = remap(ps.color, text), back = remap(ps.backgroundColor, background);
            if (!color && !back) continue;
            const id = el.dataset.quirePseudo ??= String(pseudoRules.length);
            pseudoRules.push(`[data-quire-pseudo="${id}"]${pseudo} {${color ? ` color: ${color} !important;` : ''}${back ? ` background-color: ${back} !important;` : ''} }`);
          }
        }
        // Read everything first, then write, so the styles are computed once.
        for (const [el, property, value] of plan) {
          changed.push([el, property, el.style.getPropertyValue(property), el.style.getPropertyPriority(property)]);
          el.style.setProperty(property, value, 'important');
        }
        if (pseudoRules.length) {
          const sheet = document.createElement('style');
          sheet.id = 'quire-pseudo';
          sheet.textContent = pseudoRules.join('\\n');
          document.documentElement.append(sheet);
        }
      };
      const restore = () => {
        for (const [el, property, value, priority] of changed.reverse()) el.style.setProperty(property, value, priority);
        changed.length = 0;
        document.getElementById('quire-pseudo')?.remove();
        for (const el of document.querySelectorAll('[data-quire-pseudo]')) delete el.dataset.quirePseudo;
      };
      const ready = () => document.documentElement.classList.add('quire-ready');
      addEventListener('load', () => { try { if (dark.matches) darken(); } finally { ready(); } });
      setTimeout(ready, 3000);  // never leave the page hidden, even if load is slow
      dark.addEventListener('change', () => { restore(); if (dark.matches) darken(); });

      window.quireMarkInk = (urls) => {
        const ink = new Set(urls);
        for (const img of document.images) if (ink.has(img.src)) img.classList.add('quire-ink');
      };

      let pending = false;
      window.quireReport = () => {
        pending = false;
        const max = document.documentElement.scrollHeight - innerHeight;
        webkit.messageHandlers.position.postMessage({
          fraction: max > 0 ? Math.min(1, scrollY / max) : 0,
          top: scrollY <= 1,
          bottom: scrollY >= max - 1,
        });
      };
      const schedule = () => { if (!pending) { pending = true; requestAnimationFrame(quireReport); } };
      addEventListener('scroll', schedule, { passive: true });
      addEventListener('resize', schedule);
    })();
    """

    init(book: Book, positionKey: String) {
        self.book = book
        self.positionKey = positionKey

        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        schemeHandler = BookSchemeHandler(book: book)
        config.setURLSchemeHandler(schemeHandler, forURLScheme: Book.scheme)
        config.defaultWebpagePreferences.allowsContentJavaScript = false
        webView = ReaderView(frame: .zero, configuration: config)

        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1000, height: 760),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        window.minSize = NSSize(width: 480, height: 320)
        super.init(window: window)

        config.userContentController.addUserScript(WKUserScript(source: Self.userScript, injectionTime: .atDocumentEnd,
                                                                forMainFrameOnly: true, in: .defaultClient))
        config.userContentController.add(WeakMessageHandler(self), contentWorld: .defaultClient, name: "position")
        webView.navigationDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        let zoom = UserDefaults.standard.double(forKey: "pageZoom")
        webView.pageZoom = zoom > 0 ? zoom : 1
        webView.onKeyDown = { [weak self] in self?.handleKey($0) ?? false }

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("title"))
        outline.addTableColumn(column)
        outline.outlineTableColumn = column
        outline.headerView = nil
        outline.style = .sourceList
        outline.dataSource = self
        outline.delegate = self
        let scroll = NSScrollView()
        scroll.documentView = outline
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false

        let split = NSSplitViewController()
        let sidebar = NSSplitViewItem(sidebarWithViewController: Self.wrap(scroll))
        sidebar.minimumThickness = 180
        sidebar.maximumThickness = 420
        split.addSplitViewItem(sidebar)
        split.addSplitViewItem(NSSplitViewItem(viewController: Self.wrap(webView)))
        split.splitView.autosaveName = "BookSplit"
        window.contentViewController = split
        window.setContentSize(NSSize(width: 1000, height: 760))

        let toolbar = NSToolbar(identifier: "Book")
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        window.toolbar = toolbar
        window.delegate = self
        window.setFrameAutosaveName("Book")

        outline.reloadData()

        let saved = UserDefaults.standard.dictionary(forKey: "positions")?[positionKey] as? [String: Double]
        let start = min(max(Int(saved?["chapter"] ?? 0), 0), book.spine.count - 1)
        show(chapter: start, fraction: saved?["fraction"] ?? 0)

        NotificationCenter.default.addObserver(self, selector: #selector(pageZoomChanged), name: .pageZoomChanged, object: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func windowTitle(forDocumentDisplayName displayName: String) -> String { book.title }

    private static func wrap(_ view: NSView) -> NSViewController {
        let controller = NSViewController()
        controller.view = view
        return controller
    }

    // MARK: - Navigation

    private func show(chapter index: Int, fraction: Double = 0) {
        guard book.spine.indices.contains(index) else { return }
        pendingFraction = fraction
        webView.load(URLRequest(url: book.spine[index]))
    }

    /// Opens a link target inside the book: a document, optionally with a fragment.
    private func open(_ url: URL) {
        guard let current = webView.url, Self.document(current) == Self.document(url) else {
            pendingFraction = url.fragment == nil ? 0 : nil
            webView.load(URLRequest(url: url))
            return
        }
        // Same document: just scroll, without reloading.
        let id = url.fragment(percentEncoded: false) ?? ""
        let literal = (try? String(data: JSONEncoder().encode(id), encoding: .utf8)) ?? "\"\""
        let js = id.isEmpty ? "scrollTo(0, 0)"
            : "(document.getElementById(\(literal)) || document.getElementsByName(\(literal))[0])?.scrollIntoView()"
        webView.evaluateJavaScript(js, in: nil, in: .defaultClient)
    }

    private static func document(_ url: URL) -> URL {
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.fragment = nil
        return components?.url ?? url
    }

    private func handleKey(_ event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
        switch (event.keyCode, modifiers) {
        case (49, []) where atBottom && chapter + 1 < book.spine.count:  // Space at the end: next chapter
            show(chapter: chapter + 1)
        case (49, [.shift]) where atTop && chapter > 0:  // Shift-Space at the top: end of the previous chapter
            show(chapter: chapter - 1, fraction: 1)
        case (124, []):
            nextChapter(nil)
        case (123, []):
            previousChapter(nil)
        default:
            return false
        }
        return true
    }

    @objc func nextChapter(_ sender: Any?) { show(chapter: chapter + 1) }
    @objc func previousChapter(_ sender: Any?) { show(chapter: chapter - 1) }
    @objc func goBack(_ sender: Any?) { webView.goBack() }
    @objc func goForward(_ sender: Any?) { webView.goForward() }

    @objc func zoomIn(_ sender: Any?) { setZoom(webView.pageZoom * 1.1) }
    @objc func zoomOut(_ sender: Any?) { setZoom(webView.pageZoom / 1.1) }
    @objc func actualSize(_ sender: Any?) { setZoom(1) }

    private func setZoom(_ zoom: CGFloat) {
        UserDefaults.standard.set(Double(max(0.5, min(3, zoom))), forKey: "pageZoom")
        NotificationCenter.default.post(name: .pageZoomChanged, object: nil)
    }

    @objc private func pageZoomChanged() {
        webView.pageZoom = UserDefaults.standard.double(forKey: "pageZoom")
    }

    func validateMenuItem(_ item: NSMenuItem) -> Bool { validate(item.action) }
    func validateToolbarItem(_ item: NSToolbarItem) -> Bool { validate(item.action) }

    private func validate(_ action: Selector?) -> Bool {
        switch action {
        case #selector(nextChapter(_:)): chapter + 1 < book.spine.count
        case #selector(previousChapter(_:)): chapter > 0
        case #selector(goBack(_:)): webView.canGoBack
        case #selector(goForward(_:)): webView.canGoForward
        default: true
        }
    }

    // MARK: - Reading position

    private func savePosition() {
        var positions = UserDefaults.standard.dictionary(forKey: "positions") ?? [:]
        positions[positionKey] = ["chapter": Double(chapter), "fraction": fraction]
        UserDefaults.standard.set(positions, forKey: "positions")
    }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.frameInfo.isMainFrame, let body = message.body as? [String: Any] else { return }
        fraction = body["fraction"] as? Double ?? 0
        atTop = body["top"] as? Bool ?? true
        atBottom = body["bottom"] as? Bool ?? true
        savePosition()
    }

    // MARK: - WKNavigationDelegate

    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                 decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void) {
        guard let url = action.request.url, url.scheme != Book.scheme else { return decisionHandler(.allow) }
        // Links out of the book (web pages, mail) go to the default app.
        if action.navigationType == .linkActivated { NSWorkspace.shared.open(url) }
        decisionHandler(.cancel)
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        guard let url = webView.url else { return }
        if let index = book.spine.firstIndex(where: { $0 == Self.document(url) }) {
            chapter = index
        }
        syncSelection(with: url)
        window?.toolbar?.validateVisibleItems()
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        // By now every image on the page has been served, so the handler has classified them.
        let ink = (try? JSONEncoder().encode(Array(schemeHandler.inkOnlyImages))).map { String(decoding: $0, as: UTF8.self) } ?? "[]"
        var js = "quireMarkInk(\(ink)); quireReport()"
        if let fraction = pendingFraction, fraction > 0 {
            js = "scrollTo(0, \(fraction) * (document.documentElement.scrollHeight - innerHeight)); " + js
        }
        pendingFraction = nil
        webView.evaluateJavaScript(js, in: nil, in: .defaultClient)
    }

    // MARK: - Table of contents

    private func syncSelection(with url: URL) {
        let document = Self.document(url)
        let selected = outline.item(atRow: outline.selectedRow) as? TOCItem
        // Keep the user's choice when several entries point into the same document.
        if let target = selected?.url, Self.document(target) == document { return updateSubtitle() }

        func find(_ items: [TOCItem]) -> TOCItem? {
            for item in items {
                if let target = item.url, Self.document(target) == document { return item }
                if let found = find(item.children) { return found }
            }
            return nil
        }
        syncingSelection = true
        defer { syncingSelection = false }
        if let item = find(book.toc) {
            var ancestors: [TOCItem] = []
            var parent = item.parent
            while let p = parent { ancestors.insert(p, at: 0); parent = p.parent }
            ancestors.forEach { outline.expandItem($0) }
            let row = outline.row(forItem: item)
            outline.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            outline.scrollRowToVisible(row)
        } else {
            outline.deselectAll(nil)
        }
        updateSubtitle()
    }

    private func updateSubtitle() {
        let title = (outline.item(atRow: outline.selectedRow) as? TOCItem)?.title ?? ""
        window?.subtitle = title == book.title ? "" : title
    }

    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        (item as? TOCItem)?.children.count ?? book.toc.count
    }

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        (item as? TOCItem)?.children[index] ?? book.toc[index]
    }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        !((item as? TOCItem)?.children.isEmpty ?? true)
    }

    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        let id = NSUserInterfaceItemIdentifier("cell")
        let cell = outlineView.makeView(withIdentifier: id, owner: nil) as? NSTableCellView ?? {
            let cell = NSTableCellView()
            cell.identifier = id
            let text = NSTextField(labelWithString: "")
            text.lineBreakMode = .byTruncatingTail
            text.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(text)
            cell.textField = text
            NSLayoutConstraint.activate([
                text.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 2),
                text.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -2),
                text.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            ])
            return cell
        }()
        let title = (item as? TOCItem)?.title ?? ""
        cell.textField?.stringValue = title
        cell.toolTip = title
        return cell
    }

    func outlineViewSelectionDidChange(_ notification: Notification) {
        updateSubtitle()
        guard !syncingSelection, let url = (outline.item(atRow: outline.selectedRow) as? TOCItem)?.url else { return }
        open(url)
    }

    // MARK: - Toolbar

    private static let previousItem = NSToolbarItem.Identifier("previous")
    private static let nextItem = NSToolbarItem.Identifier("next")

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.toggleSidebar, .sidebarTrackingSeparator, .flexibleSpace, Self.previousItem, Self.nextItem]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar)
    }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier id: NSToolbarItem.Identifier,
                 willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        let (label, symbol, action) = id == Self.previousItem
            ? (String(localized: "Previous Chapter"), "chevron.left", #selector(previousChapter(_:)))
            : (String(localized: "Next Chapter"), "chevron.right", #selector(nextChapter(_:)))
        let item = NSToolbarItem(itemIdentifier: id)
        item.label = label
        item.toolTip = label
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
        item.isBordered = true
        item.target = self
        item.action = action
        return item
    }
}
