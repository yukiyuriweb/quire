# Quire

A lightweight, native macOS EPUB reader that just opens a file and shows it.

Apple Books is built around a store and a library. Quire has neither: open an `.epub`, read it, close it.

- Each chapter scrolls like a web page; the table of contents sits in the sidebar
- Reopens each book where you left off
- EPUB 3 and EPUB 2 (navigation document or NCX), images, SVG, MathML and embedded fonts
- Follows the system's dark mode
- Quick Look: press Space on an `.epub` in Finder to see its cover, title and authors and the first ten or so pages, and Finder shows each book's cover as its icon
- The book's own JavaScript is turned off, and nothing is stored apart from your reading positions
- Written in Swift with AppKit and WebKit only — no Electron, no dependencies

Quire opens DRM-free EPUBs only. Books bought from Apple Books are protected by DRM and can't be opened.

## Requirements

- macOS 13 or later
- Xcode or the Xcode Command Line Tools (Swift 5.9+)

## Build

```sh
./build.sh
```

This produces `build/Quire.app`. `./build.sh --install` also copies it to `~/Applications`.

## Usage

- ⌘O opens a book; File > Open Recent lists the last ones. From Finder, use Open With > Quire, or drop a file on the Dock icon. From a terminal: `open -a Quire book.epub`.
- `Space` / `Shift-Space` scroll a screen at a time, and move on to the next chapter at the end (or back to the previous one at the top).
- `→` / `←` (or ⌥⌘→ / ⌥⌘←) go to the next / previous chapter. ⌘[ / ⌘] go back / forward after following a link.
- ⌘+ / ⌘− / ⌘0 make the text bigger, smaller or back to the default size, in every window.
- ⌃⌘S shows or hides the table of contents.

The Quick Look extensions come inside Quire.app and are registered when the app is first opened or copied to `~/Applications`. If they don't show up, open Quire once, or check System Settings > General > Login Items & Extensions > Quick Look.

Reading positions are stored in Quire's user defaults (`defaults read local.quire positions`), keyed by file path.

## License

[MIT](LICENSE)
