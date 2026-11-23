import AppKit
import CryptoKit
import ImageIO

/// A freshly captured clipboard snapshot, before it is persisted.
struct CapturedClip {
    var payload: ClipPayload
    var kind: ClipKind
    var preview: String
    var thumbnailPNG: Data?
    var imagePixelWidth: Int?
    var imagePixelHeight: Int?
    var sourceAppName: String?
    var sourceBundleID: String?
    var contentHash: String

    var byteSize: Int {
        payload.items.reduce(0) { $0 + $1.values.reduce(0) { $0 + $1.count } } + (thumbnailPNG?.count ?? 0)
    }
}

/// Polls `NSPasteboard.general` for changes. macOS has no change notification
/// for the pasteboard, so polling `changeCount` (which is cheap and does not
/// trigger the paste-privacy alert) is the standard approach.
@MainActor
final class ClipboardMonitor {
    var onCapture: ((CapturedClip) -> Void)?
    var isPaused = false

    private let pasteboard = NSPasteboard.general
    private var lastChangeCount: Int
    private var timer: Timer?

    init() {
        // -1 so whatever is on the clipboard at launch gets recorded too
        // (de-duplication makes this a no-op if it's already in history).
        lastChangeCount = -1
    }

    func start() {
        let timer = Timer(timeInterval: 0.4, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
        timer.tolerance = 0.1
        // .common so we keep capturing while a menu is open.
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    /// Call after Clipman itself writes to the pasteboard so we don't re-capture it.
    func skipCurrentChange() {
        lastChangeCount = pasteboard.changeCount
    }

    private func poll() {
        let count = pasteboard.changeCount
        guard count != lastChangeCount else { return }
        lastChangeCount = count
        guard !isPaused else { return }
        if PasteboardAccess.current == .denied { return }
        if let clip = capture() {
            onCapture?(clip)
        }
    }

    private func capture() -> CapturedClip? {
        guard let pbItems = pasteboard.pasteboardItems, !pbItems.isEmpty else { return nil }

        let allTypes = Set(pbItems.flatMap { $0.types.map(\.rawValue) })
        guard allTypes.isDisjoint(with: UTType.ignoredMarkers) else { return nil }

        var reps: [[String: Data]] = []
        for item in pbItems {
            var dict: [String: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) {
                    dict[type.rawValue] = data
                }
            }
            Self.compactImages(&dict)
            if !dict.isEmpty { reps.append(dict) }
        }
        guard !reps.isEmpty else { return nil }

        let payload = ClipPayload(items: reps)
        let source = NSWorkspace.shared.frontmostApplication
        let isSelf = source?.bundleIdentifier == Bundle.main.bundleIdentifier

        var clip = CapturedClip(
            payload: payload,
            kind: .other,
            preview: "",
            sourceAppName: isSelf ? nil : source?.localizedName,
            sourceBundleID: isSelf ? nil : source?.bundleIdentifier,
            contentHash: Self.hash(reps)
        )
        Self.classify(&clip)
        return clip
    }

    // MARK: - Helpers

    /// Screenshots and many apps put an uncompressed TIFF on the pasteboard,
    /// which can be tens of MB. Store a PNG instead; TIFF is regenerated on restore.
    static func compactImages(_ dict: inout [String: Data]) {
        guard let tiff = dict[UTType.tiff] else { return }
        if dict[UTType.png] == nil {
            guard tiff.count > 256 * 1024,
                  let rep = NSBitmapImageRep(data: tiff),
                  let png = rep.representation(using: .png, properties: [:]),
                  png.count < tiff.count
            else { return }
            dict[UTType.png] = png
        }
        dict[UTType.tiff] = nil
    }

    static func hash(_ reps: [[String: Data]]) -> String {
        var hasher = SHA256()
        for item in reps {
            for key in item.keys.sorted() {
                hasher.update(data: Data(key.utf8))
                hasher.update(data: item[key]!)
            }
            hasher.update(data: Data([0]))
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    static func classify(_ clip: inout CapturedClip) {
        let payload = clip.payload
        let first = payload.items[0]

        if first[UTType.fileURL] != nil {
            let urls = payload.fileURLs
            clip.kind = .file
            clip.preview = urls.count == 1
                ? urls[0].path
                : "\(urls.count) files: " + urls.map(\.lastPathComponent).joined(separator: ", ")
            if let url = urls.first, isImageFile(url) {
                clip.thumbnailPNG = thumbnail(from: url)
            }
            return
        }

        // Many apps (e.g. Office) attach an image rendering alongside text,
        // so text wins if present.
        if let text = payload.plainText, !text.isEmpty {
            let isRich = UTType.richTextTypes.contains { first[$0] != nil }
            clip.kind = isRich ? .richText : .text
            clip.preview = String(text.prefix(2000))
            return
        }

        if let data = payload.imageData {
            clip.kind = .image
            if let src = CGImageSourceCreateWithData(data as CFData, nil),
               let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any] {
                clip.imagePixelWidth = props[kCGImagePropertyPixelWidth] as? Int
                clip.imagePixelHeight = props[kCGImagePropertyPixelHeight] as? Int
                clip.thumbnailPNG = thumbnail(from: src)
            }
            if let w = clip.imagePixelWidth, let h = clip.imagePixelHeight {
                clip.preview = "Image \(w)×\(h)"
            } else {
                clip.preview = "Image"
            }
            return
        }

        clip.kind = .other
        clip.preview = first.keys.sorted().first ?? "Unknown content"
    }

    static func isImageFile(_ url: URL) -> Bool {
        ["png", "jpg", "jpeg", "gif", "heic", "tiff", "tif", "webp", "bmp"].contains(url.pathExtension.lowercased())
    }

    static func thumbnail(from url: URL) -> Data? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return thumbnail(from: src)
    }

    static func thumbnail(from src: CGImageSource, maxPixels: Int = 480) -> Data? {
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixels,
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else { return nil }
        return NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:])
    }
}

/// Wrapper over macOS 15.4+ `NSPasteboard.accessBehavior` ("Paste from other apps" privacy).
enum PasteboardAccess {
    case unsupported, notRequested, ask, allowed, denied

    static var current: PasteboardAccess {
        guard #available(macOS 15.4, *) else { return .unsupported }
        switch NSPasteboard.general.accessBehavior {
        case .default: return .notRequested
        case .ask: return .ask
        case .alwaysAllow: return .allowed
        case .alwaysDeny: return .denied
        @unknown default: return .ask
        }
    }
}
