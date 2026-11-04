import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = makeMenu()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.activate(ignoringOtherApps: true)
    }

    /// With nothing to open (launched from the Dock, or reopened with no windows), ask for a book.
    func applicationOpenUntitledFile(_ sender: NSApplication) -> Bool {
        NSDocumentController.shared.openDocument(nil)
        return true
    }

    private func makeMenu() -> NSMenu {
        let main = NSMenu()

        let appMenu = NSMenu()
        appMenu.addItem(withTitle: String(localized: "About Quire"), action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: String(localized: "Hide Quire"), action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(withTitle: String(localized: "Quit Quire"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        main.addItem(withTitle: "", action: nil, keyEquivalent: "").submenu = appMenu

        let fileMenu = NSMenu(title: String(localized: "File"))
        fileMenu.addItem(withTitle: String(localized: "Open…"), action: #selector(NSDocumentController.openDocument(_:)), keyEquivalent: "o")
        // AppKit fills in the recent books when it finds the "Clear Menu" item.
        let recentMenu = NSMenu(title: String(localized: "Open Recent"))
        recentMenu.addItem(withTitle: String(localized: "Clear Menu"), action: #selector(NSDocumentController.clearRecentDocuments(_:)), keyEquivalent: "")
        fileMenu.addItem(withTitle: String(localized: "Open Recent"), action: nil, keyEquivalent: "").submenu = recentMenu
        fileMenu.addItem(.separator())
        fileMenu.addItem(withTitle: String(localized: "Close"), action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        main.addItem(withTitle: "", action: nil, keyEquivalent: "").submenu = fileMenu

        let editMenu = NSMenu(title: String(localized: "Edit"))
        editMenu.addItem(withTitle: String(localized: "Copy"), action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: String(localized: "Select All"), action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        main.addItem(withTitle: "", action: nil, keyEquivalent: "").submenu = editMenu

        let viewMenu = NSMenu(title: String(localized: "View"))
        viewMenu.addItem(withTitle: String(localized: "Zoom In"), action: #selector(BookWindowController.zoomIn(_:)), keyEquivalent: "+")
        viewMenu.addItem(withTitle: String(localized: "Zoom Out"), action: #selector(BookWindowController.zoomOut(_:)), keyEquivalent: "-")
        viewMenu.addItem(withTitle: String(localized: "Actual Size"), action: #selector(BookWindowController.actualSize(_:)), keyEquivalent: "0")
        viewMenu.addItem(.separator())
        viewMenu.addItem(withTitle: String(localized: "Toggle Sidebar"), action: #selector(NSSplitViewController.toggleSidebar(_:)), keyEquivalent: "s").keyEquivalentModifierMask = [.command, .control]
        main.addItem(withTitle: "", action: nil, keyEquivalent: "").submenu = viewMenu

        let goMenu = NSMenu(title: String(localized: "Go"))
        goMenu.addItem(withTitle: String(localized: "Next Chapter"), action: #selector(BookWindowController.nextChapter(_:)), keyEquivalent: String(Character(UnicodeScalar(NSRightArrowFunctionKey)!))).keyEquivalentModifierMask = [.command, .option]
        goMenu.addItem(withTitle: String(localized: "Previous Chapter"), action: #selector(BookWindowController.previousChapter(_:)), keyEquivalent: String(Character(UnicodeScalar(NSLeftArrowFunctionKey)!))).keyEquivalentModifierMask = [.command, .option]
        goMenu.addItem(.separator())
        goMenu.addItem(withTitle: String(localized: "Back"), action: #selector(BookWindowController.goBack(_:)), keyEquivalent: "[")
        goMenu.addItem(withTitle: String(localized: "Forward"), action: #selector(BookWindowController.goForward(_:)), keyEquivalent: "]")
        main.addItem(withTitle: "", action: nil, keyEquivalent: "").submenu = goMenu

        let windowMenu = NSMenu(title: String(localized: "Window"))
        windowMenu.addItem(withTitle: String(localized: "Minimize"), action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: String(localized: "Zoom"), action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        main.addItem(withTitle: "", action: nil, keyEquivalent: "").submenu = windowMenu
        NSApp.windowsMenu = windowMenu

        return main
    }
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.regular)
    app.run()
}
