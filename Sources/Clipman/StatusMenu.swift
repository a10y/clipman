import AppKit

/// The menu bar item: recent clips, a "Recent Images" gallery submenu, and app controls.
@MainActor
final class StatusMenuController: NSObject, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let store: HistoryStore
    private let settings: Settings
    private let actions: Actions

    struct Actions {
        var choose: (ClipItem) -> Void
        var showHistory: () -> Void
        var showSettings: () -> Void
        var clearHistory: () -> Void
        var isPaused: () -> Bool
        var setPaused: (Bool) -> Void
    }

    init(store: HistoryStore, settings: Settings, actions: Actions) {
        self.store = store
        self.settings = settings
        self.actions = actions
        super.init()
        statusItem.button?.image = PaperclipIcon.menuBarImage()
        statusItem.button?.toolTip = "Clipman"
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
    }

    func refreshIcon() {
        statusItem.button?.appearsDisabled = actions.isPaused()
    }

    // Rebuild lazily each time the menu opens so it always reflects current history.
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        let recent = Array(store.items.prefix(settings.menuItemCount))
        if recent.isEmpty {
            menu.addItem(disabled("No clipboard history yet"))
        } else {
            menu.addItem(disabled("Recent"))
            for item in recent {
                menu.addItem(menuItem(for: item, thumbnailHeight: 18))
            }
        }

        let images = store.items.filter { $0.kind == .image || ($0.kind == .file && $0.hasThumbnail) }
        if !images.isEmpty {
            menu.addItem(.separator())
            let imagesItem = NSMenuItem(title: "Recent Images", action: nil, keyEquivalent: "")
            imagesItem.image = NSImage(systemSymbolName: "photo.on.rectangle", accessibilityDescription: nil)
            let sub = NSMenu()
            for item in images.prefix(20) {
                sub.addItem(menuItem(for: item, thumbnailHeight: 72))
            }
            imagesItem.submenu = sub
            menu.addItem(imagesItem)
        }

        menu.addItem(.separator())

        let show = NSMenuItem(title: "Show Clipboard History…", action: #selector(showHistory), keyEquivalent: "")
        show.target = self
        let combo = settings.hotKey
        if combo.keyName.count == 1 {
            show.keyEquivalent = combo.keyName.lowercased()
            show.keyEquivalentModifierMask = combo.cocoaModifiers
        }
        menu.addItem(show)

        let pause = NSMenuItem(title: "Pause Capturing", action: #selector(togglePause), keyEquivalent: "")
        pause.target = self
        pause.state = actions.isPaused() ? .on : .off
        menu.addItem(pause)

        let clear = NSMenuItem(title: "Clear History…", action: #selector(clearHistory), keyEquivalent: "")
        clear.target = self
        clear.isEnabled = !store.items.isEmpty
        menu.addItem(clear)

        menu.addItem(.separator())

        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(showSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(NSMenuItem(title: "Quit Clipman", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    private func disabled(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    private func menuItem(for item: ClipItem, thumbnailHeight: CGFloat) -> NSMenuItem {
        let title = item.preview.condensedWhitespace
        let truncated = title.count > 60 ? String(title.prefix(60)) + "…" : title
        let menuItem = NSMenuItem(title: truncated, action: #selector(chooseItem(_:)), keyEquivalent: "")
        menuItem.target = self
        menuItem.representedObject = item.id
        menuItem.toolTip = item.sourceAppName.map { "Copied from \($0)" }

        if let thumb = store.thumbnail(for: item) {
            menuItem.image = Self.resized(thumb, height: thumbnailHeight)
        } else if let icon = AppIconCache.icon(for: item.sourceBundleID) {
            menuItem.image = Self.resized(icon, height: 16)
        } else {
            menuItem.image = NSImage(systemSymbolName: item.kind.symbolName, accessibilityDescription: nil)
        }
        return menuItem
    }

    private static func resized(_ image: NSImage, height: CGFloat) -> NSImage {
        let aspect = image.size.height > 0 ? image.size.width / image.size.height : 1
        let size = NSSize(width: min(height * aspect, height * 2.5), height: height)
        return NSImage(size: size, flipped: false) { rect in
            image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
            return true
        }
    }

    // MARK: - Actions

    @objc private func chooseItem(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID,
              let item = store.items.first(where: { $0.id == id }) else { return }
        actions.choose(item)
    }

    @objc private func showHistory() { actions.showHistory() }
    @objc private func showSettings() { actions.showSettings() }
    @objc private func clearHistory() { actions.clearHistory() }

    @objc private func togglePause() {
        actions.setPaused(!actions.isPaused())
        refreshIcon()
    }
}
