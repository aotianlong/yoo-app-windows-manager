# Yoo Windows Manager

[English](README.md) | [简体中文](README.zh-CN.md)

A lightweight macOS window manager that arranges windows using a **binary space partitioning (BSP)** layout.

## Download

Download the prebuilt `YooWindowsManager-*-macos-arm64.app.zip` for Apple Silicon from [GitHub Releases](https://github.com/aotianlong/yoo-app-windows-manager/releases/latest), unzip it, and move the app to Applications.

The current release uses an ad-hoc signature. If macOS blocks the first launch, right-click the app in Finder and choose **Open**.

## Features

- Maintains an independent binary layout tree for each display
- Resolves window frames from the tree and applies them through the Accessibility API
- Runs in the menu bar and automatically tiles the windows on every display
- Persists layout state in `~/Library/Application Support/YooWindowsManager/`
- Follows the system language, with English and Simplified Chinese included

## Requirements

- macOS 14+
- Swift 6.0+
- **Accessibility** permission to move and resize windows
- **Input Monitoring** permission if macOS blocks global shortcuts

## Build and Run

```bash
git clone https://github.com/aotianlong/yoo-app-windows-manager.git
cd yoo-app-windows-manager
./Scripts/build-app.sh
open .build/YooWindowsManager.app
```

On first launch, the app opens the system Accessibility settings. Once permission is granted, window management continues automatically and the menu shows the current authorization state.

Launch the generated `.app` bundle instead of using `swift run`. A bare executable may not appear reliably in the macOS Accessibility list.

## Usage

The app manages windows automatically. Choose **Relayout** from the menu bar or press **Control + Shift + R** to rebuild the layout independently on every display.

Open **Settings… (Command + ,)** to configure:

- Launch at login and automatic layout after launch
- Window gap, screen edge gap, swap threshold, and detection interval
- Layout animation, drag feedback, and cross-display ordering
- Recording or disabling global shortcuts for relayout and window ordering

Adjacent windows use a 10 pt gap by default, with a 5 pt margin around the screen.

When a window edge is resized, adjacent windows expand or shrink in real time. The updated split ratio is preserved after the drag ends. Choose **Relayout** to restore strict 50/50 splits.

Window-order shortcuts operate on the focused window:

- **Control + Shift + Enter**: move to the first layout position
- **Control + Shift + I**: move one position forward
- **Control + Shift + J**: move one position backward

Automatic layouts follow this pattern:

- 1 window: fills the display
- 2 windows: equal left and right halves
- 3 windows: one on the left, two stacked on the right
- 4 windows: one on the left, one at the upper right, and two at the lower right
- More windows: each new window splits one region at 50/50, alternating horizontally and vertically

## Architecture

```text
Sources/
  YooWindowsManagerCore/     # Testable core library
    Models/                  # LayoutNode, LayoutWorkspace
    Services/                # LayoutEngine, WindowDiscovery, AX control

  YooWindowsManager/         # Menu bar application
```

### BSP Layout

1. Each display owns a layout tree. A `leaf` represents a window, while a `split` divides an area by direction and ratio.
2. The tree produces window geometry through `resolvedPlacements`.
3. `AccessibilityWindowController` applies each frame to the corresponding macOS window.

## Tests

```bash
swift test
```

## Roadmap

- Move focus between neighboring tree nodes
- Adjust a parent split ratio by dragging
- Multiple Desktop / Space awareness
- Developer ID signing and notarized releases

## License

[MIT](LICENSE)
