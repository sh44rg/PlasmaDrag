# PlasmaDrag

KDE Plasma-style window management for macOS, living in the menu bar.

| Gesture | Action |
| --- | --- |
| Option + left-drag anywhere in a window | Move the window (kept within the display under the cursor) |
| Option + two-finger drag on the trackpad | Resize by moving the bottom-right corner |
| Option + mouse wheel | Grow / shrink from the bottom-right corner |

Resizing always acts on the focused window, wherever the cursor is, and keeps
its top-left corner in place. Neither moving nor resizing lets a window extend
past the edges of its display (menu bar and Dock excluded).

A plain Option-click (no drag) still reaches the app underneath.

## Build and install

Requires the Xcode command line tools (Swift 5.10+), macOS 14+.

```sh
scripts/build-app.sh                # builds, ad-hoc signs, installs to /Applications and launches
scripts/build-app.sh --no-install   # only produce build/PlasmaDrag.app
```

Installing also removes any older copy left in `~/Applications`.

The app icon is drawn by `scripts/make-icon.swift`, which writes
`Resources/AppIcon.icns` (run it with `swift scripts/make-icon.swift` after
changing the design).

On first launch, grant access in **System Settings > Privacy & Security >
Accessibility**. PlasmaDrag starts working as soon as access is granted, with no
relaunch needed.

The menu bar icon has toggles for enabling/disabling PlasmaDrag and Launch at
Login, and an About panel with the version.

Turn on **Green Button Fills Window** in the menu bar to make a plain click on
the standard green window button expand the window within the current desktop.
Click again to restore the window's previous size and position. Full Screen
remains available from the green button's menu. The switch is off by default
and is paused when **Enabled** is off. Apps with custom title bars may continue
to use their own green-button behavior.

## Tiling

The menu bar popup has a **Tile Windows** grid of layouts: Halves, Rows,
2/3 + 1/3, Thirds, Main + 2, Quarters, Main + Stack and Grid All. Clicking one
tiles the frontmost visible windows on the display of the frontmost window,
front to back, edge to edge with no gaps. Fixed layouts take as many windows
as they have slots; Main + Stack and Grid All take every visible window on that
display. Minimized, hidden, fullscreen and dialog windows are left alone.

Dragging a tiled window out of its tile, by its title bar or with Option-drag,
gives it back the size it had before it was first tiled, with the spot you
grabbed staying under the cursor. Re-tiling a window that is still in its tile
keeps its original size; resizing a tiled window by hand makes its current
size the one to keep.

## Resource usage

Idle, PlasmaDrag uses 0% CPU, has 0 wakeups, and has a ~12 MB memory footprint.

- By default, the only always-on hook is a listen-only tap for modifier-key changes. The
  tap that intercepts mouse and scroll events is enabled only while Option is
  held, so ordinary scrolling and dragging never pass through PlasmaDrag.
- The optional green-button tap listens only for left-button presses and
  releases. It looks up the clicked window's bounds before using Accessibility
  to confirm a possible green-button hit. The resize runs in the background.
- Window geometry is written on a background queue with latest-wins
  coalescing, deduplicated to whole-point changes.
- Window lookups batch their Accessibility reads into single round-trips.
- No timers or polling, except a 1 s check while waiting for Accessibility
  permission.

## Known limitations

- **Rebuilding resets permission.** Each build gets a new ad-hoc signature,
  so macOS may treat it as a different app. If gestures stop working after a
  rebuild, remove PlasmaDrag from the Accessibility list and add it again.
- **Some windows resist.** Certain Electron/Java apps and system dialogs
  ignore or only partially honor Accessibility move/resize requests. Apps also
  enforce their own minimum/maximum sizes. Fullscreen windows are skipped.
- **Option-drag is taken over.** While enabled, app features that use
  Option-drag are unavailable: copying files in Finder, column/block text
  selection in editors, duplicating objects in design tools. Option+scroll is
  likewise used for resizing. Use the **Enabled** toggle in the menu to
  turn PlasmaDrag off temporarily.
- When a password field or Secure Keyboard Entry is active, macOS may hide
  the Option key press from PlasmaDrag, so gestures may not trigger until it ends.
- Option-clicks reach the app on mouse-up instead of mouse-down, because
  PlasmaDrag waits to see if a drag follows.
