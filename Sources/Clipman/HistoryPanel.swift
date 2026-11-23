import AppKit
import Carbon.HIToolbox
import Combine
import SwiftUI

/// A Spotlight-style floating panel. Being `.nonactivatingPanel` means it can
/// take keyboard focus *without* activating Clipman, so whatever app you were
/// in stays frontmost and ⌘V works immediately after choosing an item.
final class HistoryPanel: NSPanel {
    /// Return true if the event was handled.
    var keyHandler: ((NSEvent) -> Bool)?

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 780, height: 480),
            styleMask: [.nonactivatingPanel, .titled, .fullSizeContentView, .resizable],
            backing: .buffered,
            defer: false
        )
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isMovableByWindowBackground = true
        level = .floating
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary, .transient]
        minSize = NSSize(width: 560, height: 320)
        for button in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            standardWindowButton(button)?.isHidden = true
        }
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, let keyHandler, keyHandler(event) { return }
        super.sendEvent(event)
    }
}

@MainActor
final class HistoryPanelController: NSObject, NSWindowDelegate {
    private let panel = HistoryPanel()
    private let model: HistoryViewModel

    var isVisible: Bool { panel.isVisible }

    init(store: HistoryStore, onChoose: @escaping (ClipItem) -> Void) {
        model = HistoryViewModel(store: store)
        super.init()
        model.onChoose = { [weak self] item in
            self?.hide()
            onChoose(item)
        }
        panel.delegate = self
        panel.contentView = NSHostingView(rootView: HistoryView(model: model))
        panel.keyHandler = { [weak self] event in
            MainActor.assumeIsolated { self?.handleKey(event) ?? false }
        }
    }

    func toggle() {
        isVisible ? hide() : show()
    }

    func show() {
        model.reset()
        position()
        panel.makeKeyAndOrderFront(nil)
        model.focusSearch &+= 1
    }

    func hide() {
        panel.orderOut(nil)
    }

    func windowDidResignKey(_ notification: Notification) {
        hide()
    }

    /// Center on the screen containing the mouse, a bit above the middle.
    private func position() {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return }
        var frame = panel.frame
        frame.size.width = min(frame.width, visible.width - 40)
        frame.size.height = min(frame.height, visible.height - 40)
        frame.origin.x = visible.midX - frame.width / 2
        frame.origin.y = visible.midY - frame.height / 2 + visible.height * 0.1
        panel.setFrame(frame, display: false)
    }

    private func handleKey(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        switch Int(event.keyCode) {
        case kVK_DownArrow:
            model.move(by: 1); return true
        case kVK_UpArrow:
            model.move(by: -1); return true
        case kVK_PageDown:
            model.move(by: 10); return true
        case kVK_PageUp:
            model.move(by: -10); return true
        case kVK_Return, kVK_ANSI_KeypadEnter:
            model.chooseSelected(); return true
        case kVK_Escape:
            if model.query.isEmpty { hide() } else { model.query = "" }
            return true
        case kVK_Delete where flags.contains(.command):
            model.deleteSelected(); return true
        case kVK_ANSI_W where flags.contains(.command):
            hide(); return true
        default:
            break
        }
        // ⌘1 … ⌘9 picks the Nth visible item.
        if flags == .command, let chars = event.charactersIgnoringModifiers,
           let n = Int(chars), (1...9).contains(n) {
            model.choose(index: n - 1)
            return true
        }
        return false
    }
}

// MARK: - View model

@MainActor
final class HistoryViewModel: ObservableObject {
    let store: HistoryStore
    var onChoose: ((ClipItem) -> Void)?

    @Published var query = "" {
        didSet { selection = filtered.first?.id }
    }
    @Published var selection: UUID? {
        didSet { if selection != oldValue { loadDetail() } }
    }
    @Published private(set) var detail: Detail = .none
    /// Bumped to ask the view to focus the search field.
    @Published var focusSearch = 0

    enum Detail {
        case none
        case text(String)
        case image(NSImage)
        case files([URL])
    }

    private var cancellables = Set<AnyCancellable>()

    init(store: HistoryStore) {
        self.store = store
        store.objectWillChange
            .sink { [weak self] in self?.objectWillChange.send() }
            .store(in: &cancellables)
    }

    var filtered: [ClipItem] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return store.items }
        return store.items.filter {
            $0.preview.localizedCaseInsensitiveContains(q)
                || ($0.sourceAppName?.localizedCaseInsensitiveContains(q) ?? false)
        }
    }

    var selectedItem: ClipItem? {
        selection.flatMap { id in store.items.first { $0.id == id } }
    }

    func reset() {
        query = ""
        selection = store.items.first?.id
        loadDetail()
    }

    func move(by delta: Int) {
        let list = filtered
        guard !list.isEmpty else { return }
        let current = list.firstIndex { $0.id == selection } ?? -1
        let next = max(0, min(list.count - 1, current + delta))
        selection = list[next].id
    }

    func chooseSelected() {
        if let item = selectedItem { onChoose?(item) }
    }

    func choose(index: Int) {
        let list = filtered
        guard list.indices.contains(index) else { return }
        onChoose?(list[index])
    }

    func choose(_ item: ClipItem) {
        onChoose?(item)
    }

    func deleteSelected() {
        guard let item = selectedItem else { return }
        let list = filtered
        let idx = list.firstIndex(of: item) ?? 0
        store.delete([item.id])
        let remaining = filtered
        selection = remaining.isEmpty ? nil : remaining[min(idx, remaining.count - 1)].id
    }

    private func loadDetail() {
        guard let item = selectedItem, let payload = store.payload(for: item) else {
            detail = .none
            return
        }
        switch item.kind {
        case .text, .richText:
            detail = .text(payload.plainText ?? item.preview)
        case .image:
            if let data = payload.imageData, let image = NSImage(data: data) {
                detail = .image(image)
            } else {
                detail = .none
            }
        case .file:
            detail = .files(payload.fileURLs)
        case .other:
            detail = .text(payload.items.flatMap(\.keys).sorted().joined(separator: "\n"))
        }
    }
}
