# PlasmaDrag

KDE Plasma-style window management for macOS, living in the menu bar.

| Gesture | Action |
| --- | --- |
| Option + left-drag anywhere in a window | Move the window (kept within the display under the cursor) |
| Option + two-finger drag on the trackpad | Resize by moving the bottom-right corner |
| Option + mouse wheel | Grow / shrink from the bottom-right corner |

Resizing always acts on the focused window, wherever the cursor is, and keeps
its top-left corner in place.

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
- Option-clicks reach the app on mouse-up instead of mouse-down, because
  PlasmaDrag waits to see if a drag follows.
