# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 项目与必读文档

VideoSniffer 是**个人自用**的 iOS App（内置浏览器 + 网页视频嗅探 + 下载管理），基于上游 [LSX-s-Software/M3U8-Downloader](https://github.com/LSX-s-Software/M3U8-Downloader)（MIT）二次开发。下载引擎来自上游；浏览与嗅探（`M3U8 Downloader/Browser/`）为新增实现，**尚未通过 CI 编译、也未在真机验证**。

- [Docs/HANDOFF.md](Docs/HANDOFF.md) 是权威的交接文档：缺口清单、按 PR 顺序的实现方案、陷阱清单、验收标准。改动前先读它。
- [AGENTS.md](AGENTS.md) 是代码风格与协作规则（Swift 6 并发、SwiftUI 现代 API）。其规则同样适用于你。
- [README.md](README.md) 描述产物、装机流程（Windows + Sideloadly）和合规约束。

## 关键环境约束：本地无法编译

开发机是 **Linux**，没有 Xcode、macOS SDK 或模拟器。因此：

- **唯一的编译验证手段是 GitHub Actions 的 macOS runner**。改完代码推分支、看 CI、再迭代。
- 不要声称"已修复编译问题"；未经 CI，只能说"按代码推断可以编译"。UI 行为只能由用户在 iPhone 上实测。
- 本地能做的检查：`jq` 校验 JSON、YAML 语法、`git diff` 审查、`grep` 搜索。
- `.github/workflows/build.yml` 已就绪（`macos-26` runner，`push main` / PR / `workflow_dispatch` 触发，产物 `VideoSniffer-unsigned-ipa`）。CI 里**只构建 iOS**（`generic/platform=iOS`），不跑测试。
- 面向用户的文字用中文；提交按 `feat: / fix: / docs: …` 约定，`main` 为基线，开发走特性分支 + PR。

## 构建与测试命令

无签名 IPA（CI 或任意 macOS 机器）。**必须显式指定 iOS destination**，否则会因工程同时支持 macOS 而构建错误平台；scheme 名含空格必须加引号：

```bash
xcodebuild \
  -scheme "M3U8 Downloader" \
  -destination 'generic/platform=iOS' \
  -configuration Release \
  -derivedDataPath build \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY=""

mkdir Payload && cp -R "build/Build/Products/Release-iphoneos/M3U8 Downloader.app" Payload/
ditto -c -k --sequesterRsrc --keepParent Payload VideoSniffer-unsigned.ipa
```

单元测试（Swift Testing，模拟器设备名随 runner 变化，先 `xcrun simctl list devices available` 再选）：

```bash
xcodebuild test \
  -scheme "M3U8 Downloader" \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:"M3U8 DownloaderTests" \
  CODE_SIGNING_ALLOWED=NO
```

单条测试：

```bash
xcodebuild test -scheme "M3U8 Downloader" \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:"M3U8 DownloaderTests/M3U8DownloaderTests/mediaPlaylistParsesRelativeSegmentsAndAESKey"
```

- **不要默认跑 UI 测试**（启动慢、易 flaky；`testSettingsSheetOpens` 依赖先切到下载 Tab，见下文）。
- 集成测试被 `#if os(iOS) && RUN_MUX_HLS_INTEGRATION_TESTS` 包住，默认不跑，需要真实网络。
- 文案目录校验：`jq empty "M3U8 Downloader/Localizable.xcstrings"`。
- Demo 模式（内存数据库 + 示例任务）：`--demo-mode` 或 `M3U8_DOWNLOADER_DEMO_MODE=1`。

## 架构

```
M3U8 Downloader/               # app target（目录名沿用上游）
├── M3U8_DownloaderApp.swift   # @main：建 ModelContainer、注入 SettingsStore / downloadRuntimeMode
├── ContentView.swift          # 根视图：iOS 为 Browse / Downloads 两个 Tab，macOS 直接是 DownloadNavigationView
├── Browser/                   # 内置浏览器 + 嗅探（BrowserViewModel、BrowserView、SniffingScript、SniffMessageHandler 等）
├── Models/                    # SwiftData：DownloadJob ⇄ DownloadSegment（cascade 删除）
├── Services/                  # HLS 解析、分片下载、AES-128、组装、本地播放服务
├── Settings/                  # SettingsStore（UserDefaults + Keychain）、ProxyConfiguration
├── Utilities/                 # 路径/文件名、Keychain、启动参数、PreviewSamples
└── Views/                     # 下载列表 / 详情 / 设置 / 播放器 / 侧栏
```

**下载引擎调用链**（新增嗅探→下载入口时要挂钩的位置）：

```
DownloadEngine.run(jobID:)
 ├─ prepare(_:)                     # 状态 → .preparing，建 URLSession，解析播放列表并建 DownloadSegment
 │    ├─ fetchText(url:session:)    # 抓 m3u8 文本（未来透传 Referer/Cookie/UA 的落点）
 │    └─ HLSPlaylistParser.parseResolved(text:sourceURL:loader:)
 ├─ downloadSegments(_:)            # withThrowingTaskGroup 控制并发，SegmentRequest → SegmentDownloader
 │    └─ SegmentDownloader.download → fetchData(...) / decrypt(...)（AES key 也走 fetchData）
 ├─ MediaAssembler.assemble(job:)   # 组装（平台分支，见下表）
 └─ 写 job.finalFilePath / 状态
```

关键类型与职责：

- `DownloadEngine`（`@MainActor @Observable`，每个 `ContentView` / macOS Settings scene 一个实例）持有 `activeTasks`，所有入口先判 `mode == .normal`，Demo 模式下不改变数据。
- `DownloadFileStore`：磁盘布局的唯一权威。任务目录 `Documents/Downloads/{tempDirectoryName}/`，分片在 `Segments/`，最终产物在同一任务目录内。
- `SettingsStore.makeURLSessionConfiguration()` 是唯一构造 `URLSessionConfiguration` 的地方（超时、代理）。
- `LocalHLSServer` 是 iOS 播放本地 HLS 的 `NWListener`（`127.0.0.1`，支持 Range），用 `NSLock` 包装共享状态并标注 `@unchecked Sendable`。

### iOS 与 macOS 的实质差异（CI 只编译 iOS）

| 能力 | iOS | macOS |
| --- | --- | --- |
| 组装结果 | 本地 `.m3u8` 播放列表（引用 `Segments/`） | 合并 `.ts`/`.mp4` 后用 `AVAssetExportSession` 导出 `.mp4` |
| `DownloadFileStore.finalMediaURL` | 任务目录内的 `{outputFileName}.m3u8` | 用户选定的 `.mp4` 路径 |
| 播放 | 启动 `LocalHLSServer` + `AVPlayerViewController` | `AVPlayerView` |

**改动原则：只动 iOS 分支**。CI 构建 `generic/platform=iOS`，`#if os(macOS)` 分支（`AVAssetExportSession`、`NSSavePanel`、`Settings` scene 等）不参与编译，语法错误不会被发现；若不得不改，在 PR 中标注"macOS 分支未验证"。

## 工程约定（必须遵守）

- **新增 `.swift` 文件不需要改 `project.pbxproj`**：工程是 `objectVersion = 77` + `PBXFileSystemSynchronizedRootGroup`，三个同步根组是 `M3U8 Downloader` / `M3U8 DownloaderTests` / `M3U8 DownloaderUITests`。测试文件必须放进测试目录，否则会被编进 app。pbxproj 只用于新增 target、Build Settings 等高风险改动。
- **并发**：app target 配置 `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` + `SWIFT_APPROACHABLE_CONCURRENCY = YES`，因此所有类型默认 `@MainActor`。跨 actor 传递的数据必须显式 `nonisolated struct … : Sendable`（范例：`SegmentRequest`、`SegmentResult`、`HLSPlaylist` 系列）。
- **SwiftData 演进**：`DownloadJob.init` / `SegmentRequest` 的成员初始化器在测试与预览里被直接调用，**新增字段一律带默认值**，不改既有参数顺序，不把既有属性改成非可选。
- **本地化**：`Localizable.xcstrings` 使用 `extractionState: manual` 的英文短语 key，双语 `en` + `zh-Hans`，代码里通过生成符号访问（如 `Text(.downloads)`、`Button(.settings, systemImage:)`）。新增文案必须两种语言齐全，不要用字面量字符串。
- **UI**：一个文件一个类型；视图逻辑放进 ViewModel/模型以便测试；UI 测试只用稳定的 accessibility identifier，不依赖外网或文本内容。
- **测试框架**：单元测试用 Swift Testing（`import Testing`、`@Test`、`#expect`、`try #require`）；UI 测试用 XCTest（`XCUIApplication`）。
- 禁止第三方依赖；不引入 Swift Package（需要先征得用户同意）。

## 常见陷阱

- `Settings` 按钮位于下载侧栏工具栏（`Views/DownloadSidebarView.swift`）。Tab 结构下 App 启动落在 Browse 页，UI 测试必须先点 `app.buttons["downloadsTab"]`（Tab 上了 `accessibilityIdentifier`，比本地化标题稳）。
- UI 测试目标 `SWIFT_VERSION = 5.0`，app 目标 `6.0`；两者独立编译，不要据此推断 app 的并发规则。
- 工程当前 `IPHONEOS_DEPLOYMENT_TARGET = 18.0`、`MACOSX_DEPLOYMENT_TARGET = 26.0`；README 写的是 iOS 26 运行目标。使用新 API 前确认最低部署版本，不能假设 iOS 26。
- 不要为了取 Cookie 去绕过鉴权，也不要为了转载 Cookie 而禁用页面的 HttpOnly 设置；Cookie 应来自 `WKHTTPCookieStore` 而非 `document.cookie`。
- 上游签名的 `DEVELOPMENT_TEAM`（`C2A3XCXCZS`）与 Bundle ID（`LSX-s-Software.*`）**必须替换为自有值**，且不得推测他人的 Team ID。
- 仓库中永不存放密钥、证书、Apple ID、密码、Cookie/token；调试日志也不要打印完整 Cookie 或 Authorization 头。
- 合规红线：仅个人使用、不上架；只处理非 DRM 内容与 HLS 明文 AES-128 密钥，绝不实现 FairPlay/Widevine 绕过，也不添加绕过登录/付费墙的功能。上游 MIT 署名（`LICENSE`、两份 README）必须保留。
