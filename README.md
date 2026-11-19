<p align="center">
  <img src="Support/icon.png" width="128" height="128" alt="MinimalCapture icon">
</p>

<h1 align="center">MinimalCapture</h1>

<p align="center">
  A tiny macOS menu bar screenshot tool. Press a shortcut, the capture is on your clipboard and saved to disk.<br>
  No editor, no cloud, no account, about 12 MB of memory while idle.
</p>

---

## What it does

| Shortcut | Action |
|---|---|
| <kbd>⇧</kbd><kbd>⌘</kbd><kbd>3</kbd> | Capture the whole screen (the display your pointer is on) |
| <kbd>⇧</kbd><kbd>⌘</kbd><kbd>4</kbd> | Drag to capture an area. <kbd>Esc</kbd>, a right-click or a plain click cancels |
| <kbd>⇧</kbd><kbd>⌘</kbd><kbd>V</kbd> | Show the last 20 captures. Click one to put it back on the clipboard |

Every capture is copied to the clipboard straight away and saved as a PNG named like
`Capture-2026-11-19-18.39.10.png`.

From the menu bar icon you can also:

- **Change Save Folder…** — captures go to the Desktop unless you pick somewhere else.
- **Keep Only Latest 20** — on by default. Older `Capture-*.png` files in the save folder are
  deleted after each capture; nothing else in the folder is ever touched. Turn it off to keep
  everything.
- **Start at Login**.

## Install

1. Download `MinimalCapture.zip` from the [latest release](../../releases/latest) and unzip it.
2. Move `MinimalCapture.app` to your Applications folder and open it.
3. The release build is not notarised by Apple, so macOS will block it the first time.
   Open **System Settings → Privacy & Security**, scroll down, and click **Open Anyway**.
4. Grant **Screen Recording** when the app asks. If macOS offers *Quit & Reopen*, accept it.
5. Free up the shortcuts: in **System Settings → Keyboard → Keyboard Shortcuts… → Screenshots**,
   untick the built-in ⇧⌘3 and ⇧⌘4 entries. Quit any other screenshot tool that uses them.

Requires macOS 14 or later. Developed and tested on macOS 27 on Apple silicon; the release
build is universal, but the Intel half is untested.

> **Heads-up:** while MinimalCapture is running, ⇧⌘V belongs to it everywhere. Some apps use
> that shortcut for "Paste and Match Style".

## Build from source

You need Xcode 26 or later (Swift 6.2).

```bash
git clone https://github.com/glennsheff/MinimalCapture.git
cd MinimalCapture
./build-app.sh
open build/MinimalCapture.app
```

`build-app.sh` signs the app with the first code-signing identity in your keychain, or ad-hoc
if you have none. With an ad-hoc signature macOS treats every rebuild as a new app and asks for
Screen Recording again, so a certificate (a free *Apple Development* one from Xcode is enough)
saves a lot of clicking.

The icon is drawn in code. To change it, edit `Support/make-icon.swift` and run
`swift Support/make-icon.swift`.

## How it works

It is a Swift package with no dependencies and no Xcode project.

| File | Role |
|---|---|
| `AppDelegate.swift` | Menu bar item, settings, and the capture pipeline |
| `HotKeyCenter.swift` | Global shortcuts through Carbon's `RegisterEventHotKey` |
| `SelectionOverlay.swift` | The dimmed drag-to-select overlay |
| `CaptureEngine.swift` | One-shot capture with ScreenCaptureKit |
| `CaptureStore.swift` | PNG encoding, file naming, the rolling queue, thumbnails |
| `Clipboard.swift` | Pasteboard writes |
| `HistoryPanel.swift` | The floating history panel |
| `Permissions.swift` | Screen Recording onboarding |

A few choices that keep it small and out of the way:

- **Carbon hotkeys, not an event tap.** No Accessibility permission is needed, and the
  shortcuts keep working while a password field has Secure Input on.
- **Windows are created on demand and destroyed.** The overlay and the history panel exist
  only while they are on screen.
- **The clipboard gets PNG bytes, not an `NSImage`.** An `NSImage` on the pasteboard stays
  alive in the app, pinning the uncompressed bitmap (about 24 MB for a Retina screen). PNG
  bytes are handed to the system and nothing is retained; macOS still offers TIFF to apps that
  ask for it. The same bytes are written to disk, so each capture is compressed once.
- **History thumbnails come straight from ImageIO**, one file at a time, so the full-size
  images are never all in memory together.
- **The app never becomes the frontmost app.** The window you are capturing keeps its active
  appearance, and you can paste immediately after picking from the history.

### Things worth knowing

- The app is not sandboxed; global hotkeys require that.
- Showing a crosshair while another app is frontmost uses a non-public window-server setting.
  If a future macOS removes it, the pointer simply stays an arrow during selection.
- There is no window-capture mode, annotation, or text recognition.

## Licence

[MIT](LICENSE)
