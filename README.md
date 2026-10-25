# ExtraDock

A macOS menu bar app that mirrors your Dock on every connected monitor. macOS only shows the Dock on one display at a time — ExtraDock fixes that by rendering a faithful, interactive copy on all your screens.

> ### Fork notice / 派生说明
>
> This is a **public fork** of [henningziech/extradock](https://github.com/henningziech/extradock) by **Henning Ziech**. All original credit belongs to the original author; this fork retains the **MIT** license.
>
> 本仓库基于 Henning Ziech 的 [henningziech/extradock](https://github.com/henningziech/extradock) 公开派生，原作者保留全部著作权，许可证沿用 **MIT**。

### Improvements in this fork / 本派生版本做的优化改进

- **修复：点击 dock 图标无法调出应用（原生 dock 可以）**
  - 原因：原代码使用 `app.activate()`（无参数，已废弃），从后台/非激活 app 调用时不会把目标 app 推到前台，点击看似无反应。
  - 修复：改为 `app.activate(options: .activateIgnoringOtherApps)`，并补充 `app.isHidden` 时 `unhide()`，与原生 dock 行为一致（强推前台、自动切换所在桌面、取消隐藏）。
- **优化：dock 外观更接近原生**
  - 背景材质由深色 `.hudWindow`（HUD 灰）改为浅色磨砂 `.popover`，保留 vibrancy 毛玻璃，圆角 16 → 20，整体观感更贴近系统 dock。
  - 运行指示点由「4px 白圆点 + 图标被上推」改为「图标居中 + 底部居中的小胶囊形指示」，对齐原生 dock 样式。

> 改动文件：`ExtraDock/Views/DockItemView.swift`、`ExtraDock/Windows/MirrorDockPanel.swift`

## Features

- Mirrors pinned apps, recent apps, and persistent folders from your real Dock
- Running-app indicator dots
- Click to launch or switch to apps
- Folders open in Finder on click
- Live sync: updates within seconds when you change your Dock
- Per-monitor toggle in Settings
- Frosted glass appearance matching macOS aesthetics
- Launch at login support
- Menu-bar-only app (no Dock icon of its own)

## Requirements

- macOS 15 (Sequoia) or later
- Xcode 16+ (for building from source)

## Installation

### Quick Install (build script)

```bash
git clone https://github.com/henningziech/extradock.git
cd extradock
./install.sh
```

### Manual Build

```bash
git clone https://github.com/henningziech/extradock.git
cd extradock

# Build release
xcodebuild -project ExtraDock.xcodeproj -scheme ExtraDock -configuration Release build

# Find the built app
open ~/Library/Developer/Xcode/DerivedData/ExtraDock-*/Build/Products/Release/
```

Then drag `ExtraDock.app` to your `/Applications` folder.

### From Xcode

1. Open `ExtraDock.xcodeproj` in Xcode
2. Select the ExtraDock scheme
3. Build & Run (Cmd+R)

## Usage

1. Launch ExtraDock — it appears as a dock icon in the menu bar
2. A mirror dock bar appears at the bottom of each connected external monitor
3. Click the menu bar icon for:
   - **Settings** — toggle monitors, adjust tile size, enable launch at login
   - **Refresh Dock** — force a re-read of your Dock configuration
   - **Quit**

## How It Works

ExtraDock reads your Dock configuration from `~/Library/Preferences/com.apple.dock.plist` and monitors it for changes. It uses `NSWorkspace` to track running applications and renders everything in floating `NSPanel` windows positioned at the bottom of each screen.

## Not Sandboxed

ExtraDock needs direct access to the Dock preferences plist and process activation APIs, so it cannot be sandboxed. It is not eligible for the Mac App Store. Distribute via direct download (ideally signed with Developer ID and notarized).

## License

MIT
