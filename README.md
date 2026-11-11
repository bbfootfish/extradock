# ExtraDock

A macOS menu bar app that mirrors your Dock on every connected monitor. macOS only shows the Dock on one display at a time — ExtraDock fixes that by rendering a faithful, interactive copy on all your screens.

> ### Fork notice / 派生说明
>
> This is a **public fork** of [henningziech/extradock](https://github.com/henningziech/extradock) by **Henning Ziech**. All original credit belongs to the original author; this fork retains the **MIT** license.
>
> 本仓库基于 Henning Ziech 的 [henningziech/extradock](https://github.com/henningziech/extradock) 公开派生，原作者保留全部著作权，许可证沿用 **MIT**。

### Improvements in this fork / 本派生版本做的优化改进

Upstream baseline / 上游基线：`henningziech/extradock` @ `e9cdd80`（Fix dock scale: use observable DockState.scale for consistent sizing）。
以下为本 fork 在该基线之上的全部改动，每项注明它替换掉的上游原有行为。

**1. 修复：点击 dock 图标无法调出应用（commit `f8a726a`，`d016a09` 重写）**
- 上游行为：使用无参 `app.activate()`（已废弃），从后台/非激活 app 调用时不会把目标 app 推到前台，点击看似无反应。
- 本 fork：先 `unhide()`，再 `NSWorkspace.openApplication(activates: true)`，最后 `activate(.activateAllWindows)`。中间版本曾用 `activateIgnoringOtherApps`，该选项在 macOS 14+ 已被系统忽略，故弃用。已是前台/运行中的应用也能被切到前台，隐藏应用可被唤起。

**2. 优化：dock 外观更接近原生（commit `f8a726a`）**
- 背景材质由 `.hudWindow`（HUD 灰）改为浅色磨砂 `.popover`，保留 vibrancy 毛玻璃，圆角 16 → 20。
- 运行指示点由「4px 白圆点 + 图标被上推」改为「图标居中 + 底部居中的胶囊形指示」。

**3. 补齐系统固定项：Finder 与废纸篓（commit `f247fc8`）**
- 上游行为：只读 `com.apple.dock.plist` 的瓦片数据；但在 macOS（尤其 Tahoe）下 Finder 与废纸篓由 Dock 自身渲染、**不写入该 plist**，因此原版永远缺失这两项。
- 本 fork：在 `DockConfigReader` 中合成——`Finder` 置最左、`废纸篓` 置最右，随 `trash-full` 切换空/满图标，点击行为与原生一致。

**4. 修复崩溃 + 列表与系统 Dock 对齐（commit `d016a09`）**
- 崩溃（主因）：`DockState.updateItems` 用 `Dictionary(uniqueKeysWithValues:)` 按路径建表，当同一应用同时出现在 `persistent-apps` 与 `recent-apps` 时重复键触发 `fatalError` 直接闪退；2 秒轮询反复重载，表现为「用着用着就消失」。本 fork 改为 `reduce` 合并，并在解析时按路径去重。
- 列表不一致：上游只读固定项与最近项，缺少**运行中但未固定**的应用（实测漏 5 个）。`RunningAppsMonitor` 改为输出全部 Dock 可见的前台型应用并按启动时间排序；合并顺序对齐系统（访达 → 固定 → 运行中未固定 → 最近 → 文件夹/废纸篓），按路径 + bundleID 双重去重。
- 渲染：由「固定 | 最近 | 其他」三段（两根分隔线）改为单一应用区 + 一根分隔线，与系统一致；并遵循 `show-recents` 开关。

**5. 只在副屏显示，主屏屏蔽（commit `b7d5db7`）**
- 上游行为：每块连接的显示器都创建镜像面板。
- 本 fork：以 `NSScreen.screens.first`（拥有菜单栏的屏幕）判定主显示器，按 displayID 比对且每次刷新实时计算、不缓存；`refreshPanels()` 先求目标集合 `targetDisplayIDs()`（排除主屏 + 过滤每屏开关）再统一收敛——目标外的面板销毁，目标内的创建或重定位。设置中主屏那行置灰并标注 `Main — mirror dock off`，`isEnabled()` 对主屏强制返回 `false`。屏幕插拔、主屏切换、分辨率变化由 `didChangeScreenParametersNotification` 自动跟随。

**6. 修复：每次重建后辅助功能授权失效（稳定本地签名）**
- 问题：ad-hoc 签名（`CODE_SIGN_IDENTITY="-"`）的 designated requirement 退化为按 `cdhash` 精确匹配。ExtraDock 需要辅助功能权限（`AXIsProcessTrusted`，用于读取 Dock 徽标与右键菜单），而 macOS TCC 按代码签名要求记录授权；重新编译后二进制变化 → `cdhash` 变化 → 系统视其为陌生 app，授权静默失效，必须每次去「系统设置 → 隐私与安全性 → 辅助功能」重新勾选。
- 方案：改用固定的本地自签代码签名证书 `ExtraDock Local Signing`（10 年有效）。DR 从按 `cdhash` 匹配变为 `identifier "com.henningziech.ExtraDock" and certificate root = H"..."`——只锚定证书，重建不改变 DR，授权得以保留。
- 落地：`scripts/setup_local_signing.sh` 一键生成证书与独立钥匙串（私钥 `-A` + `set-key-partition-list`，签名无需 GUI 交互）；用户域信任用 `add-trusted-cert -o` 生成设置文件再 `trust-settings-import` 导入，避开直接执行时的认证弹窗；构建脚本改用 `CODE_SIGN_IDENTITY="ExtraDock Local Signing"` + `OTHER_CODE_SIGN_FLAGS="--timestamp=none"`，并在安装后校验 DR。
- 一次性成本：从 ad-hoc 换成证书签名时，需**重新授权一次**辅助功能；此后重建不再需要。
- 边界：证书与私钥仅存于本机 `~/.extradock-signing/`（已加入 `.gitignore`），**不随仓库分发**；Gatekeeper 仍会拒绝（无 Developer ID / 公证），本地构建解除 quarantine 后可正常运行。对外分发应改用 Developer ID + 公证。

> 改动文件（相对上游 `e9cdd80`）：上述 Swift 源文件（10 个）、`LICENSE`、`README.md`、`.gitignore`、`scripts/setup_local_signing.sh`。签名证书与私钥只存本机，不入库。

## Features

- Mirrors pinned apps, recent apps, and persistent folders from your real Dock
- Running-app indicator dots
- Click to launch or switch to apps
- Folders open in Finder on click
- Live sync: updates within seconds when you change your Dock
- Shown only on secondary displays — the main display (the one owning the menu bar) is excluded automatically and follows primary-display changes
- Per-monitor toggle in Settings (the main display row is locked off)
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

### Stable local signing (recommended if you rebuild often)

An ad-hoc signature causes macOS to drop the **Accessibility** grant on every rebuild, because the designated requirement matches `cdhash`. Sign with a fixed local certificate instead:

```bash
bash scripts/setup_local_signing.sh       # one-time; creates cert + dedicated keychain
```

```bash
CODE_SIGN_STYLE=Manual \
CODE_SIGN_IDENTITY="ExtraDock Local Signing" \
OTHER_CODE_SIGN_FLAGS="--timestamp=none" \
xcodebuild -project ExtraDock.xcodeproj -scheme ExtraDock -configuration Release build
```

Verify the requirement is certificate-anchored:

```bash
codesign -dr - path/to/ExtraDock.app
# designated => identifier "com.henningziech.ExtraDock" and certificate root = H"..."
```

After switching from ad-hoc, re-enable ExtraDock once in **System Settings → Privacy & Security → Accessibility**. Later rebuilds keep the grant. The certificate and private key stay in `~/.extradock-signing/` on your Mac and must never be committed.

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
