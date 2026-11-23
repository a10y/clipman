import AppKit
import Combine

@main
enum ClipmanMain {
    @MainActor
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory) // menu bar only, no Dock icon
        app.run()
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settings = Settings.shared
    private var store: HistoryStore!
    private var monitor: ClipboardMonitor!
    private var statusMenu: StatusMenuController!
    private var panel: HistoryPanelController!
    private var settingsWindow: SettingsWindowController!
    private var retentionTimer: Timer?
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        store = HistoryStore()
        enforceRetention()

        monitor = ClipboardMonitor()
        monitor.onCapture = { [weak self] clip in
            guard let self else { return }
            guard clip.byteSize <= self.settings.maxBytes else { return }
            self.store.add(clip)
            self.enforceRetention()
        }

        panel = HistoryPanelController(store: store) { [weak self] item in
            self?.restore(item)
        }
        settingsWindow = SettingsWindowController(store: store, settings: settings)

        statusMenu = StatusMenuController(store: store, settings: settings, actions: .init(
            choose: { [weak self] in self?.restore($0) },
            showHistory: { [weak self] in self?.panel.show() },
            showSettings: { [weak self] in self?.settingsWindow.show() },
            clearHistory: { [weak self] in self?.confirmClearHistory() },
            isPaused: { [weak self] in self?.monitor.isPaused ?? false },
            setPaused: { [weak self] in self?.monitor.isPaused = $0 }
        ))

        HotKeyCenter.shared.onTrigger = { [weak self] in self?.panel.toggle() }
        HotKeyCenter.shared.register(settings.hotKey)

        settings.$hotKey
            .dropFirst()
            .removeDuplicates()
            .sink { HotKeyCenter.shared.register($0) }
            .store(in: &cancellables)

        Publishers.CombineLatest(settings.$retentionDays, settings.$maxStorageMiB)
            .dropFirst()
            .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
            .sink { [weak self] _, _ in self?.enforceRetention() }
            .store(in: &cancellables)

        // Age-based expiry happens even when nothing new is copied.
        let timer = Timer(timeInterval: 10 * 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.enforceRetention() }
        }
        RunLoop.main.add(timer, forMode: .common)
        retentionTimer = timer

        monitor.start()
    }

    /// Put a history item back on the system clipboard, ready to paste.
    private func restore(_ item: ClipItem) {
        if store.writeToPasteboard(item) {
            monitor.skipCurrentChange()
            store.touch(item)
        } else {
            NSSound.beep()
        }
    }

    private func enforceRetention() {
        store.enforceRetention(maxAge: settings.maxAge, maxBytes: settings.maxBytes)
    }

    private func confirmClearHistory() {
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = "Clear all clipboard history?"
        alert.informativeText = "This permanently deletes \(store.items.count) items."
        alert.addButton(withTitle: "Clear History")
        alert.addButton(withTitle: "Cancel")
        alert.buttons.first?.hasDestructiveAction = true
        if alert.runModal() == .alertFirstButtonReturn {
            store.clearAll()
        }
    }
}
