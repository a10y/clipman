import AppKit
import SwiftUI

struct HistoryView: View {
    @ObservedObject var model: HistoryViewModel
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            searchBar
            Divider()
            if model.filtered.isEmpty {
                emptyState
            } else {
                HStack(spacing: 0) {
                    list.frame(minWidth: 280, idealWidth: 340, maxWidth: 380)
                    Divider()
                    DetailPane(item: model.selectedItem, detail: model.detail)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            Divider()
            footer
        }
        .background(.regularMaterial)
        .ignoresSafeArea()  // reclaim the hidden titlebar strip
        .onChange(of: model.focusSearch) { searchFocused = true }
        .onAppear { searchFocused = true }
    }

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .font(.title3)
            TextField("Search clipboard history", text: $model.query)
                .textFieldStyle(.plain)
                .font(.title3)
                .focused($searchFocused)
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 12)
    }

    private var list: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(Array(model.filtered.enumerated()), id: \.element.id) { index, item in
                        ClipRow(item: item, index: index, store: model.store,
                                isSelected: item.id == model.selection)
                            .id(item.id)
                            .contentShape(Rectangle())
                            .onTapGesture(count: 2) { model.choose(item) }
                            .onTapGesture { model.selection = item.id }
                            .contextMenu {
                                Button("Copy") { model.choose(item) }
                                Button("Delete") {
                                    model.selection = item.id
                                    model.deleteSelected()
                                }
                            }
                    }
                }
                .padding(6)
            }
            .onChange(of: model.selection) { _, id in
                guard let id else { return }
                proxy.scrollTo(id)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: model.query.isEmpty ? "paperclip" : "magnifyingglass")
                .font(.system(size: 36))
                .foregroundStyle(.tertiary)
            Text(model.query.isEmpty ? "Nothing copied yet" : "No matches")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var footer: some View {
        HStack(spacing: 14) {
            hint("↩", "Copy")
            hint("⌘1–9", "Quick pick")
            hint("⌘⌫", "Delete")
            hint("esc", "Close")
            Spacer()
            Text("\(model.store.items.count) items · \(ByteCountFormatter.string(fromByteCount: Int64(model.store.totalBytes), countStyle: .memory))")
                .foregroundStyle(.secondary)
        }
        .font(.caption)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    private func hint(_ key: String, _ label: String) -> some View {
        HStack(spacing: 4) {
            Text(key)
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(RoundedRectangle(cornerRadius: 4).fill(.quaternary))
            Text(label).foregroundStyle(.secondary)
        }
    }
}

struct ClipRow: View {
    let item: ClipItem
    let index: Int
    let store: HistoryStore
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 10) {
            ClipIcon(item: item, store: store, size: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.preview.condensedWhitespace)
                    .lineLimit(2)
                    .truncationMode(.tail)
                    .font(.body)
                HStack(spacing: 4) {
                    if let app = item.sourceAppName { Text(app) }
                    Text(item.date, format: .relative(presentation: .named))
                }
                .font(.caption)
                .foregroundStyle(isSelected ? AnyShapeStyle(.white.opacity(0.8)) : AnyShapeStyle(.secondary))
            }
            Spacer(minLength: 4)
            if index < 9 {
                Text("⌘\(index + 1)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(isSelected ? AnyShapeStyle(.white.opacity(0.8)) : AnyShapeStyle(.tertiary))
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .foregroundStyle(isSelected ? .white : .primary)
        .background(
            RoundedRectangle(cornerRadius: 7)
                .fill(isSelected ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.clear))
        )
    }
}

/// Thumbnail for images, otherwise the source app's icon with a kind badge.
struct ClipIcon: View {
    let item: ClipItem
    let store: HistoryStore
    let size: CGFloat

    var body: some View {
        Group {
            if let thumb = store.thumbnail(for: item) {
                Image(nsImage: thumb)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: size, height: size)
                    .clipShape(RoundedRectangle(cornerRadius: 5))
            } else if let appIcon = AppIconCache.icon(for: item.sourceBundleID) {
                Image(nsImage: appIcon)
                    .resizable()
                    .frame(width: size, height: size)
                    .overlay(alignment: .bottomTrailing) {
                        Image(systemName: item.kind.symbolName)
                            .font(.system(size: size * 0.3, weight: .semibold))
                            .padding(2)
                            .background(Circle().fill(.background))
                            .offset(x: 3, y: 3)
                    }
            } else {
                Image(systemName: item.kind.symbolName)
                    .font(.system(size: size * 0.55))
                    .frame(width: size, height: size)
            }
        }
    }
}

struct DetailPane: View {
    let item: ClipItem?
    let detail: HistoryViewModel.Detail

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            if let item {
                Divider()
                metadata(item)
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch detail {
        case .none:
            Color.clear
        case .text(let text):
            ScrollView {
                Text(text.count > 20_000 ? String(text.prefix(20_000)) + "…" : text)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(14)
            }
        case .image(let image):
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(14)
        case .files(let urls):
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(urls, id: \.self) { url in
                        HStack {
                            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                                .resizable().frame(width: 32, height: 32)
                            VStack(alignment: .leading) {
                                Text(url.lastPathComponent)
                                Text(url.deletingLastPathComponent().path)
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .padding(14)
            }
        }
    }

    private func metadata(_ item: ClipItem) -> some View {
        HStack(spacing: 12) {
            Label(item.kind.label, systemImage: item.kind.symbolName)
            if let w = item.imagePixelWidth, let h = item.imagePixelHeight {
                Text("\(w)×\(h)")
            }
            Text(ByteCountFormatter.string(fromByteCount: Int64(item.byteSize), countStyle: .memory))
            Spacer()
            Text(item.date, format: .dateTime.month().day().hour().minute())
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }
}

extension ClipKind {
    var label: String {
        switch self {
        case .text: return "Text"
        case .richText: return "Rich Text"
        case .image: return "Image"
        case .file: return "File"
        case .other: return "Other"
        }
    }
}

extension String {
    /// Collapse runs of whitespace/newlines into single spaces for one-line previews.
    var condensedWhitespace: String {
        split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}

@MainActor
enum AppIconCache {
    private static var cache: [String: NSImage] = [:]

    static func icon(for bundleID: String?) -> NSImage? {
        guard let bundleID else { return nil }
        if let cached = cache[bundleID] { return cached }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        cache[bundleID] = icon
        return icon
    }
}
