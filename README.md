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
scripts/build-app.sh            # builds, ad-hoc signs, installs to ~/Applications
scripts/build-app.sh --no-install   # only produce build/PlasmaDrag.app
open ~/Applications/PlasmaDrag.app
```

On first launch, grant access in **System Settings > Privacy & Security >
Accessibility**. PlasmaDrag starts working as soon as access is granted, with no
relaunch needed.

The menu bar icon has toggles for enabling/disabling PlasmaDrag and Launch at Login.

## Resource usage

Idle, PlasmaDrag uses 0% CPU, has 0 wakeups, and has a ~12 MB memory footprint.

- The only always-on hook is a listen-only tap for modifier-key changes. The
  tap that intercepts mouse and scroll events is enabled only while Option is
  held, so ordinary scrolling and dragging never pass through PlasmaDrag.
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
