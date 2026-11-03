# CLAUDE.md

Quire is a lightweight, native macOS EPUB reader (Swift + AppKit + WebKit, no dependencies, no Xcode project). It opens a file and shows it: no library, store or sync.

## Build and run

- `./build.sh` builds a release binary, then assembles `build/Quire.app`, adds the icon and ad-hoc signs it. `./build.sh --install` also copies it to `~/Applications`, replacing any copy there.
- `swift build -c release` alone is enough to check that the code compiles.
- The app icon is drawn by `scripts/make-icon.swift`; `build.sh` regenerates it on every build. Don't commit image files for it.
- Swift language mode is 5 (`swift-tools-version:5.9`). `main.swift` wraps app startup in `MainActor.assumeIsolated`.
- Two Quick Look extensions are built by `build.sh` with `swiftc` (not SwiftPM: an `.appex` starts at `_NSExtensionMain`) and embedded in `Contents/PlugIns`: `QuirePreview` (`Extensions/Preview`, a data-based HTML preview: cover, title, authors, then about ten pages built by `Excerpt` in the preview's own style, since Quick Look runs no JavaScript and the app's dark-mode darkening can't run there) and `QuireThumbnail` (`Extensions/Thumbnail`, the cover as the Finder icon). Both compile `Sources/Quire/Zip.swift` and `Book.swift` in, so keep those two files free of AppKit/WebKit and of anything else from the app. Extensions are signed with `Extensions/Extension.entitlements` (sandbox) before the app is signed.
- The app is document-based: `Info.plist` (written by `build.sh`) declares `org.idpf.epub-container` with `NSDocumentClass` `Document`, which is why the class is `@objc(Document)`. `NSDocumentController` provides Open, Open Recent, Finder opening and window restoration.

## Workflow

- The repository is `yukiyuriweb/quire` on GitHub. The initial code went in through a one-off `develop` branch. After that is merged, cut one branch per issue from `main`. Open a PR to `main`; merge with **squash only** (the repo only allows squash, and deletes the head branch on merge).
- Commits, PRs, README and code comments are in English. UI strings are written in English with `String(localized:)`, and their Japanese translations live in `Localization/ja.lproj/Localizable.strings` (`build.sh` copies it into the app). Add every new UI string to that file.

## Conventions in the code

- **Never extract the EPUB to disk.** `ZipArchive` reads the archive into memory (not memory-mapped, so rebuilding the file while it is open can't crash the app), and `BookSchemeHandler` serves its files to the web view as `quire://book/<path in archive>`. Relative links, images and stylesheets resolve as they do in the archive.
- **The book's JavaScript stays off** (`allowsContentJavaScript = false`). Quire's own script runs in `WKContentWorld.defaultClient`, which that setting doesn't affect; run any app JavaScript there too (`evaluateJavaScript(_:in: nil, in: .defaultClient)`).
- **The injected stylesheet must use px, not em/rem**, for widths and padding: fixed-layout books set `font-size: 0` on the root, which turns em-based widths into zero. It is prepended to `<head>` so the book's own CSS wins, except for the `!important` measure and dark-mode colours.
- **Reading position is a spine index plus a scroll fraction (0...1)**, saved on every scroll report in `UserDefaults` `positions`, keyed by file path. Not by `dc:identifier`: pandoc generates a new one on every build.
- The chapter is updated in `didCommit` (before the page's scroll reports start); the saved fraction is applied in `didFinish`.
- **Dark mode** (only when the system is dark; light mode shows the book as authored):
  - The book's own colours are darkened in JavaScript on `load` (`darken` in the user script): every HTML element's computed text, background and border colour gets its lightness flipped, keeping hue and chroma (not HSL saturation, which would turn off-white paper brown). Set on every element, not only where it differs from the parent, since a rule may set the same colour again. `::before`/`::after` colours go into a generated stylesheet keyed by `data-quire-pseudo`. Everything is recorded and restored when the appearance changes. The body stays hidden (`.quire-ready`) until this has run, to avoid a white flash; a timeout shows it regardless.
  - Images are skipped by `darken`. They get a white background so dark drawings on transparency stay visible, except inline `<svg>` drawn in `currentColor` (MathJax), which follows the text colour, and SVG images that are black-and-grey only (`Book.isInkOnlySVG`, shared with the preview; e.g. equations converted from a PDF), which are inverted instead: the handler classifies each SVG as it serves it, and `didFinish` passes the list to `quireMarkInk`, which adds `.quire-ink`.
- Links out of the book (http, mailto) open in the default app; the web view only navigates within `quire://`.
- XML is parsed with Foundation's `XMLDocument`, matching elements and attributes by local name so namespace prefixes don't matter.

## Verifying changes

- Screen capture is usually unavailable to the agent. To check the UI, temporarily add a hook that renders the window with `cacheDisplay(in:to:)` and the page with `WKWebView.takeSnapshot` to PNGs and quits, launch with `open -W -n -a "$PWD/build/Quire.app" --env ... <book.epub> --args -ApplePersistenceIgnoreState YES`, inspect the images, then remove the hook before committing. Without `-ApplePersistenceIgnoreState`, books from earlier runs are restored too.
- Quick Look: `lsregister -f build/Quire.app` registers the extensions (check with `pluginkit -mAv -i local.quire.preview`). `qlmanage -t -x -s 256 -o <dir> <book.epub>` exercises the thumbnail extension; use `-x` (through quicklookd, as Finder does), since without it qlmanage hangs. `qlmanage -p` crashes with "key cannot be nil" for data-based preview extensions (Skim's too), so check the preview HTML by compiling `Extensions/Preview/PreviewPage.swift` and `Excerpt.swift` with `Book.swift` and `Zip.swift` and rendering its output (write attachments with file extensions and replace the `cid:` references, or WebKit won't recognise SVG), and the extension itself with Space in Finder.
- To test parsing without the UI, compile `Sources/Quire/Zip.swift` and `Sources/Quire/Book.swift` together with a throwaway `main.swift` outside the repo using `swiftc`.
- Useful test books: a pandoc-built EPUB 3 with SVG equation images, an EPUB with a nested navigation document, one with only an NCX, and a fixed-layout (pre-paginated) Japanese book.
- To open a test book at a given place, add its position with `defaults write local.quire positions -dict-add <key> '<dict>…</dict>'` (`-dict` replaces every stored position). The key is the NFC `standardizedFileURL` path, so `/private/tmp/…` becomes `/tmp/…`.
- A test run writes reading positions and window frames to the real `local.quire` defaults; leave them as you found them.

## Background

- A quire is a gathering of folded sheets, the unit a book is sewn from.
- Built to replace Apple Books for reading DRM-free EPUBs, without its store and library.
- Features deliberately left out so far: paginated (page-turn) display, vertical Japanese text, proper fixed-layout support (pages just scroll one per chapter), library, highlights, notes, search, and sync.
