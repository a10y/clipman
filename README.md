# Clipman

A small native macOS clipboard manager (Swift, AppKit + SwiftUI, no dependencies).

- Records everything copied to the system clipboard (text, rich text, images, files), with every pasteboard representation kept intact.
- The menu bar paperclip shows recent items, plus a **Recent Images** submenu with thumbnails.
- **⌃⌘X** (configurable) opens a searchable history panel. Choosing an item puts it back on the clipboard, ready for ⌘V. The panel never takes focus away from the app you're in.
- History is kept for **3 days** or **100 MiB**, whichever limit is hit first (both configurable). The oldest items are removed first.
- Skips items that password managers mark as concealed or transient (see [nspasteboard.org](http://nspasteboard.org)).

## Build & run

Requires Xcode (just installed; it does not need to be selected with `xcode-select`).

```sh
make run       # debug build → build/Clipman.app, launched
make app       # release build → build/Clipman.app
make install   # release build copied to /Applications and launched
make test      # unit tests
make icon      # regenerate Resources/AppIcon.icns from PaperclipIcon.swift
```

## History panel keys

| Key | Action |
| --- | --- |
| type | filter |
| ↑ / ↓, PgUp / PgDn | move selection |
| ↩ or double-click | copy to clipboard and close |
| ⌘1 – ⌘9 | copy the Nth item |
| ⌘⌫ | delete the selected item |
| esc | clear the search, then close |

## Notes

- **Clipboard privacy (macOS 15.4+)**: macOS may ask before Clipman reads the clipboard. Choose *Always Allow*, or set it under System Settings › Privacy & Security › Paste from Other Apps. Builds are ad-hoc signed by default, which can make macOS forget that choice after each rebuild. Signing with a stable identity avoids this: `CODESIGN_IDENTITY="Apple Development: …" make app`.
- **Storage**: `~/Library/Application Support/Clipman/` holds `index.json` (metadata) and `blobs/` (payload plists and thumbnails). Large TIFFs are stored as PNG, and TIFF is regenerated when the item is restored.
- **Launch at login** uses `SMAppService` and works best from `/Applications` (`make install`).

## Layout

```
Sources/Clipman/
  ClipmanApp.swift        entry point, AppDelegate wiring
  ClipboardMonitor.swift  pasteboard polling, capture, classification, thumbnails
  HistoryStore.swift      persistence, de-dup, restore to pasteboard
  Retention.swift         age/size eviction policy (pure, unit-tested)
  Settings.swift          UserDefaults-backed prefs, HotKeyCombo
  HotKey.swift            Carbon RegisterEventHotKey wrapper
  HistoryPanel.swift      non-activating floating panel + view model
  HistoryView.swift       SwiftUI history list and preview pane
  StatusMenu.swift        menu bar item and menu
  SettingsView.swift      settings window, shortcut recorder
  PaperclipIcon.swift     paperclip drawing for the menu bar glyph and app icon
scripts/                  build-app.sh, make-icon.sh, icon renderer
```
