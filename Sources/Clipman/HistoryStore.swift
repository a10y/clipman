import AppKit
import Combine

/// Persistent clipboard history.
///
/// Layout under `~/Library/Application Support/Clipman/`:
///   index.json          – [ClipItem], newest first
///   blobs/<id>.plist    – binary-plist ClipPayload
///   blobs/<id>.png      – thumbnail (images only)
@MainActor
final class HistoryStore: ObservableObject {
    @Published private(set) var items: [ClipItem] = []

    let directory: URL
    private let blobDir: URL
    private let indexURL: URL
    private let io = DispatchQueue(label: "clipman.store.io", qos: .utility)
    private let thumbCache = NSCache<NSUUID, NSImage>()

    var totalBytes: Int { items.reduce(0) { $0 + $1.byteSize } }

    init(directory: URL? = nil) {
        let base = directory ?? FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Clipman", isDirectory: true)
        self.directory = base
        self.blobDir = base.appendingPathComponent("blobs", isDirectory: true)
        self.indexURL = base.appendingPathComponent("index.json")
        try? FileManager.default.createDirectory(at: blobDir, withIntermediateDirectories: true)
        load()
    }

    // MARK: - Mutations

    func add(_ clip: CapturedClip) {
        if let idx = items.firstIndex(where: { $0.contentHash == clip.contentHash }) {
            touch(items[idx])
            return
        }

        let item = ClipItem(
            id: UUID(),
            date: Date(),
            kind: clip.kind,
            preview: clip.preview,
            byteSize: clip.byteSize,
            contentHash: clip.contentHash,
            sourceAppName: clip.sourceAppName,
            sourceBundleID: clip.sourceBundleID,
            imagePixelWidth: clip.imagePixelWidth,
            imagePixelHeight: clip.imagePixelHeight,
            hasThumbnail: clip.thumbnailPNG != nil
        )
        items.insert(item, at: 0)

        let payloadURL = payloadURL(item.id)
        let thumbURL = thumbnailURL(item.id)
        let payload = clip.payload
        let thumb = clip.thumbnailPNG
        io.async {
            let encoder = PropertyListEncoder()
            encoder.outputFormat = .binary
            if let data = try? encoder.encode(payload) {
                try? data.write(to: payloadURL, options: .atomic)
            }
            if let thumb { try? thumb.write(to: thumbURL, options: .atomic) }
        }
        saveIndex()
    }

    /// Move an existing item to the top of history (e.g. after re-copying it).
    func touch(_ item: ClipItem) {
        guard let idx = items.firstIndex(where: { $0.id == item.id }) else { return }
        var updated = items.remove(at: idx)
        updated.date = Date()
        items.insert(updated, at: 0)
        saveIndex()
    }

    func delete(_ ids: Set<UUID>) {
        guard !ids.isEmpty else { return }
        items.removeAll { ids.contains($0.id) }
        let urls = ids.flatMap { [payloadURL($0), thumbnailURL($0)] }
        for id in ids { thumbCache.removeObject(forKey: id as NSUUID) }
        io.async {
            for url in urls { try? FileManager.default.removeItem(at: url) }
        }
        saveIndex()
    }

    func clearAll() {
        delete(Set(items.map(\.id)))
    }

    func enforceRetention(maxAge: TimeInterval, maxBytes: Int) {
        delete(Retention.evictions(in: items, maxAge: maxAge, maxBytes: maxBytes))
    }

    // MARK: - Reading

    func payload(for item: ClipItem) -> ClipPayload? {
        let url = payloadURL(item.id)
        // Ensure any pending write for this item has landed.
        return io.sync {
            guard let data = try? Data(contentsOf: url) else { return nil }
            return try? PropertyListDecoder().decode(ClipPayload.self, from: data)
        }
    }

    func thumbnail(for item: ClipItem) -> NSImage? {
        guard item.hasThumbnail else { return nil }
        if let cached = thumbCache.object(forKey: item.id as NSUUID) { return cached }
        let url = thumbnailURL(item.id)
        let image = io.sync { NSImage(contentsOf: url) }
        if let image { thumbCache.setObject(image, forKey: item.id as NSUUID) }
        return image
    }

    /// Put an item back on the system pasteboard with all its original representations.
    @discardableResult
    func writeToPasteboard(_ item: ClipItem, pasteboard: NSPasteboard = .general) -> Bool {
        guard let payload = payload(for: item) else { return false }
        let pbItems: [NSPasteboardItem] = payload.items.map { dict in
            let pbItem = NSPasteboardItem()
            for (type, data) in dict {
                pbItem.setData(data, forType: NSPasteboard.PasteboardType(type))
            }
            // We drop TIFF at capture time; regenerate it for apps that only read TIFF.
            if dict[UTType.tiff] == nil, let png = dict[UTType.png],
               let tiff = NSBitmapImageRep(data: png)?.tiffRepresentation {
                pbItem.setData(tiff, forType: .tiff)
            }
            return pbItem
        }
        pasteboard.clearContents()
        return pasteboard.writeObjects(pbItems)
    }

    // MARK: - Persistence

    private func payloadURL(_ id: UUID) -> URL {
        blobDir.appendingPathComponent("\(id.uuidString).plist")
    }

    private func thumbnailURL(_ id: UUID) -> URL {
        blobDir.appendingPathComponent("\(id.uuidString).png")
    }

    private func load() {
        guard let data = try? Data(contentsOf: indexURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        items = (try? decoder.decode([ClipItem].self, from: data)) ?? []
        // Drop index entries whose payload went missing.
        items.removeAll { !FileManager.default.fileExists(atPath: payloadURL($0.id).path) }
        cleanOrphanBlobs()
    }

    private func saveIndex() {
        let snapshot = items
        let url = indexURL
        io.async {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            if let data = try? encoder.encode(snapshot) {
                try? data.write(to: url, options: .atomic)
            }
        }
    }

    private func cleanOrphanBlobs() {
        let known = Set(items.map(\.id.uuidString))
        let dir = blobDir
        io.async {
            let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
            for file in files where !known.contains(file.deletingPathExtension().lastPathComponent) {
                try? FileManager.default.removeItem(at: file)
            }
        }
    }
}
