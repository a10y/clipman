import AppKit
import ServiceManagement
import SwiftUI

@MainActor
final class SettingsWindowController {
    private var window: NSWindow?
    private let store: HistoryStore
    private let settings: Settings

    init(store: HistoryStore, settings: Settings) {
        self.store = store
        self.settings = settings
    }

    func show() {
        if window == nil {
            let hosting = NSHostingController(rootView: SettingsView(settings: settings, store: store))
            let window = NSWindow(contentViewController: hosting)
            window.title = "Clipman Settings"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}

struct SettingsView: View {
    @ObservedObject var settings: Settings
    @ObservedObject var store: HistoryStore
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var launchError: String?
    @State private var confirmClear = false

    var body: some View {
        Form {
            Section("Shortcut") {
                LabeledContent("Show clipboard history") {
                    HotKeyRecorder(combo: $settings.hotKey)
                }
            }

            Section {
                Stepper(value: $settings.retentionDays, in: 1...90) {
                    LabeledContent("Keep history for", value: "\(settings.retentionDays) day\(settings.retentionDays == 1 ? "" : "s")")
                }
                Stepper(value: $settings.maxStorageMiB, in: 10...10_240, step: 10) {
                    LabeledContent("Maximum storage", value: "\(settings.maxStorageMiB) MiB")
                }
                LabeledContent("Currently using") {
                    Text("\(ByteCountFormatter.string(fromByteCount: Int64(store.totalBytes), countStyle: .memory)) · \(store.items.count) items")
                }
                HStack {
                    Spacer()
                    Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([store.directory]) }
                    Button("Clear History…", role: .destructive) { confirmClear = true }
                        .disabled(store.items.isEmpty)
                }
            } header: {
                Text("History")
            } footer: {
                Text("The oldest items are removed once either limit is reached.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Menu Bar") {
                Stepper(value: $settings.menuItemCount, in: 5...50) {
                    LabeledContent("Recent items in menu", value: "\(settings.menuItemCount)")
                }
            }

            Section("General") {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in setLaunchAtLogin(enabled) }
                if let launchError {
                    Text(launchError).font(.caption).foregroundStyle(.red)
                }
                PasteboardAccessRow()
            }
        }
        .formStyle(.grouped)
        .frame(width: 480)
        .fixedSize(horizontal: false, vertical: true)
        .confirmationDialog("Clear all clipboard history?", isPresented: $confirmClear) {
            Button("Clear History", role: .destructive) { store.clearAll() }
        } message: {
            Text("This permanently deletes \(store.items.count) items.")
        }
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            launchError = nil
        } catch {
            launchError = error.localizedDescription
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
}

/// macOS 15.4+ asks before an app reads the clipboard programmatically.
/// A clipboard manager needs "Always Allow".
struct PasteboardAccessRow: View {
    @State private var access = PasteboardAccess.current

    var body: some View {
        LabeledContent("Clipboard access") {
            HStack {
                Text(label).foregroundStyle([.allowed, .unsupported].contains(access) ? Color.secondary : Color.orange)
                Button("Open Privacy Settings…") {
                    let urls = [
                        "x-apple.systempreferences:com.apple.preference.security?Privacy_Pasteboard",
                        "x-apple.systempreferences:com.apple.preference.security?Privacy",
                    ]
                    for s in urls {
                        if let url = URL(string: s), NSWorkspace.shared.open(url) { break }
                    }
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            access = PasteboardAccess.current
        }
    }

    private var label: String {
        switch access {
        case .unsupported: return "Allowed"
        case .allowed: return "Always allowed"
        case .denied: return "Denied — nothing is captured"
        case .ask: return "Asks each time"
        case .notRequested: return "Not yet requested"
        }
    }
}

/// Click, then press a key combination (must include ⌘, ⌃ or ⌥). Esc cancels.
struct HotKeyRecorder: View {
    @Binding var combo: HotKeyCombo
    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
        HStack(spacing: 6) {
            Button {
                recording ? stop() : start()
            } label: {
                Text(recording ? "Type shortcut…" : combo.displayString)
                    .frame(minWidth: 110)
                    .font(.body.monospaced())
            }
            .buttonStyle(.bordered)
            .tint(recording ? .accentColor : nil)

            if combo != .default {
                Button {
                    combo = .default
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                }
                .buttonStyle(.borderless)
                .help("Reset to \(HotKeyCombo.default.displayString)")
            }
        }
        .onDisappear { stop() }
    }

    private func start() {
        recording = true
        // Don't let the current hotkey fire while the user is typing a new one.
        HotKeyCenter.shared.unregister()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 { // esc
                stop()
                return nil
            }
            if let new = HotKeyCombo(event: event) {
                combo = new
                stop()
            } else {
                NSSound.beep()
            }
            return nil
        }
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        if recording {
            recording = false
            HotKeyCenter.shared.register(combo)
        }
    }
}
