import AppKit
import Combine
import SwiftUI

@main
enum LumaApplication {
    @MainActor
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        withExtendedLifetime(delegate) { app.run() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var state: AppState!
    private var window: NSWindow!
    private var statusItem: NSStatusItem!
    private var cancellable: AnyCancellable?

    func applicationDidFinishLaunching(_ notification: Notification) {
        state = AppState()
        makeMenu()
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1180, height: 795), styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        window.title = "Luma"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.minSize = NSSize(width: 980, height: 700)
        window.backgroundColor = NSColor(srgbRed: 0.063, green: 0.071, blue: 0.086, alpha: 1)
        window.contentView = NSHostingView(rootView: LibraryView(state: state))
        window.center()
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "sun.horizon", accessibilityDescription: "Luma wallpapers")
        refreshStatusMenu()
        cancellable = state.objectWillChange.sink { [weak self] in
            DispatchQueue.main.async { self?.refreshStatusMenu() }
        }
        state.restorePlayback()
        showLibrary()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showLibrary()
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationWillTerminate(_ notification: Notification) { state?.shutdown() }
    func applicationDidBecomeActive(_ notification: Notification) { state?.applicationActive = true }
    func applicationDidResignActive(_ notification: Notification) { state?.applicationActive = false }
    func windowWillClose(_ notification: Notification) { state.previewVisible = false }
    func windowDidMiniaturize(_ notification: Notification) { state.previewVisible = false }
    func windowDidDeminiaturize(_ notification: Notification) { state.previewVisible = true }

    @objc private func showLibrary() {
        state.previewVisible = true
        window.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    @objc private func togglePaused() { state.togglePaused() }
    @objc private func toggleMuted() { state.muted.toggle() }
    @objc private func clearAll() { state.clearAll() }
    @objc private func importWallpaper() { showLibrary(); state.importWallpaper() }
    @objc private func quit() { NSApplication.shared.terminate(nil) }

    private func refreshStatusMenu() {
        guard statusItem != nil else { return }
        let menu = NSMenu()
        let status = NSMenuItem(title: state.status, action: nil, keyEquivalent: "")
        status.isEnabled = false
        menu.addItem(status)
        menu.addItem(.separator())
        addItem("Open Luma", action: #selector(showLibrary), to: menu)
        addItem(state.manuallyPaused ? "Resume Wallpapers" : "Pause Wallpapers", action: #selector(togglePaused), to: menu)
        addItem(state.muted ? "Unmute Audio" : "Mute Audio", action: #selector(toggleMuted), to: menu)
        addItem("Add Wallpaper…", action: #selector(importWallpaper), to: menu)
        menu.addItem(.separator())
        addItem("Restore macOS Wallpapers", action: #selector(clearAll), to: menu)
        addItem("Quit Luma", action: #selector(quit), to: menu, key: "q")
        statusItem.menu = menu
    }

    private func addItem(_ title: String, action: Selector, to menu: NSMenu, key: String = "") {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        menu.addItem(item)
    }

    private func makeMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        addItem("About Luma", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), to: appMenu)
        appMenu.items.last?.target = NSApplication.shared
        appMenu.addItem(.separator())
        addItem("Open Library", action: #selector(showLibrary), to: appMenu, key: "l")
        addItem("Add Wallpaper…", action: #selector(importWallpaper), to: appMenu, key: "o")
        appMenu.addItem(.separator())
        addItem("Hide Luma", action: #selector(NSApplication.hide(_:)), to: appMenu, key: "h")
        appMenu.items.last?.target = NSApplication.shared
        addItem("Quit Luma", action: #selector(quit), to: appMenu, key: "q")
        appItem.submenu = appMenu
        main.addItem(appItem)
        let edit = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
        let editMenu = NSMenu(title: "Edit")
        for (title, selector, key) in [("Undo", Selector(("undo:")), "z"), ("Cut", #selector(NSText.cut(_:)), "x"), ("Copy", #selector(NSText.copy(_:)), "c"), ("Paste", #selector(NSText.paste(_:)), "v"), ("Select All", #selector(NSText.selectAll(_:)), "a")] {
            editMenu.addItem(withTitle: title, action: selector, keyEquivalent: key)
        }
        edit.submenu = editMenu
        main.addItem(edit)
        NSApplication.shared.mainMenu = main
    }
}
