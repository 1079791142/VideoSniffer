# VideoSniffer 开发交接文档（远程 Linux Agent 版）

> 本文档面向接手本仓库的远程 Claude Code agent。基线提交：`f7bfbb6`（上游 HLS 引擎原样导入，未改动源码）。
> 本文所有 `文件:行号` 均以该提交为准，改动后请以符号名定位。

---

## 0. 先读这一段：你的工作方式

你运行在 **Linux** 上。你能读写代码、提交、推送、运行 shell 脚本，但**不能编译 SwiftUI / SwiftData / WebKit，也没有 Xcode、模拟器和 macOS SDK**。

因此：

1. **唯一的编译与验证手段是 GitHub Actions 的 macOS runner**。改完代码就推分支，看 CI 结果，再迭代。
2. **不要凭猜测宣布"已修复编译问题"**。没跑过 CI 之前，只能说"按代码推断应该可以编译"。
3. **UI 行为只能由用户在 Windows 上用 Sideloadly 装到 iPhone 后实测**。CI 只能证明"能编译、能出 IPA"。
4. 本地可以做的检查：JSON 语法（`jq` 校验 `Localizable.xcstrings`）、YAML 语法、`git diff` 审查、正则搜索。**不能**跑 `xcodebuild`。
5. 所有面向用户的文字**用中文**。

仓库：<https://github.com/1079791142/VideoSniffer.git>（public，Actions 免费额度）。
分支：`main` 为基线；开发请开分支（如 `feat/browser-sniffer`），通过 PR 合并。

---

## 1. 当前状态

### 已完成（来自上游 LSX-s-Software/M3U8-Downloader，MIT）

- HLS 主列表 / 变体列表解析，选择最高码率变体
- AES-128 解密、`EXT-X-MAP` 初始化分片、`EXT-X-BYTERANGE`
- 分片并发下载（并发数可配 1…24）、指数退避重试、暂停 / 继续 / 重试 / 取消 / 删除
- 组装：macOS 导出 `.mp4`；**iOS 生成一个引用 `Segments/` 目录的本地 `.m3u8` 播放列表**
- iOS 本地 HLS 播放服务（`LocalHLSServer`，`127.0.0.1`，支持 Range）
- SwiftData 任务模型与持久化、下载列表 / 详情 / 设置 / 存储占用界面
- 中英文界面、深色模式、Demo 模式（`--demo-mode` / `M3U8_DOWNLOADER_DEMO_MODE=1`）
- 单元测试：HLS 解析、文件存储、删除、设置

### 未实现（你的任务）

1. 内置浏览器（WKWebView）与 浏览 / 下载 两个 Tab
2. 网页视频嗅探（JS 注入 + 消息桥）
3. Referer / Cookie / User-Agent 透传（防盗链站点必需）
4. 直接下载 MP4（不走 HLS 分片）
5. 工程清理（签名 team、Bundle ID、ATS、显示名）
6. `.github/workflows/build.yml` 产出未签名 IPA
7. 新增界面文案（中英文）

---

## 2. 构建与验证：GitHub Actions

### 2.1 先写 CI（这是第一个 PR）

**没有 CI 你就没有反馈回路**，所以第一步是把工作流建起来。

创建 `.github/workflows/build.yml`：

```yaml
name: Build Unsigned IPA

on:
  push:
    branches: [ main ]
  pull_request:
  workflow_dispatch:

jobs:
  build-ipa:
    runs-on: macos-26          # 需要 Xcode 26；若该标签不可用，退回 macos-latest 并检查 xcodebuild -version
    timeout-minutes: 30
    steps:
      - uses: actions/checkout@v4

      - name: Show toolchain
        run: |
          xcodebuild -version
          xcode-select -p
          xcrun --sdk iphoneos --show-sdk-version

      - name: Build (unsigned)
        run: |
          xcodebuild \
            -scheme "M3U8 Downloader" \
            -destination 'generic/platform=iOS' \
            -configuration Release \
            -derivedDataPath build \
            CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY=""

      - name: Package IPA
        run: |
          mkdir Payload
          cp -R "build/Build/Products/Release-iphoneos/M3U8 Downloader.app" Payload/
          ditto -c -k --sequesterRsrc --keepParent Payload VideoSniffer-unsigned.ipa

      - uses: actions/upload-artifact@v4
        with:
          name: VideoSniffer-unsigned-ipa
          path: VideoSniffer-unsigned.ipa
          retention-days: 30
```

要点：

- **必须显式 `-destination 'generic/platform=iOS'`**。工程同时支持 macOS（`SUPPORTED_PLATFORMS = "iphoneos iphonesimulator macosx"`），不指定 destination 时 `xcodebuild` 可能选到 macOS 平台，随后会因为 `MACOSX_DEPLOYMENT_TARGET = 26.0` 或 `#if os(macOS)` 分支而失败。
- **scheme 名带空格**：`-scheme "M3U8 Downloader"`，必须加引号。scheme 文件在 `M3U8 Downloader.xcodeproj/xcshareddata/xcschemes/`。
- 不要在 YAML 里硬编码 `xcode-select` 的 Xcode 路径（不同 runner 镜像不一致），先打印版本再判断。
- runner 标签若不可用，job 会一直排队，不会报错。怀疑"卡住"时先换成 `macos-latest` 或 `macos-15` 试一次，对比 `xcodebuild -version`。
- 产物 `.ipa` 未签名，下载后在 Windows 上交给 Sideloadly 签名。

### 2.2 可选的单元测试 job（后加）

单元测试需要模拟器。设备名随 runner 变化，**先列出来再选**：

```bash
xcrun simctl list devices available
# 例如：iPhone 17 / iPhone 16
```

然后：

```bash
xcodebuild test \
  -scheme "M3U8 Downloader" \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:"M3U8 DownloaderTests" \
  CODE_SIGNING_ALLOWED=NO
```

注意：

- 只跑 `M3U8 DownloaderTests`（纯逻辑，快）。**不要默认跑 UI Tests**：`M3U8_DownloaderUITests` 启动慢、易 flaky，而且 `testSettingsSheetOpens` 依赖界面结构（见 §5.3）。
- 集成测试被 `#if os(iOS) && RUN_MUX_HLS_INTEGRATION_TESTS` 包住，默认不跑，需要真实网络，CI 不开。
- 测试 target 是 `SWIFT_VERSION = 5.0`，app target 是 `6.0`，这没问题（两者分别编译）。

---

## 3. 架构地图

```
M3U8 Downloader/                 # app target（目录名沿用上游）
├── ContentView.swift            # 根视图（现阶段只有下载界面）
├── M3U8_DownloaderApp.swift     # @main，SwiftData 容器、SettingsStore 注入
├── Models/                      # DownloadJob / DownloadSegment / 状态与分类枚举
├── Services/                    # HLS 解析、分片下载、AES-128、组装、本地播放服务
├── Settings/                    # SettingsStore / ProxyConfiguration
├── Utilities/                   # 路径、Keychain、启动参数、文件名处理、PreviewSamples
├── Views/                       # 下载列表 / 详情 / 设置 / 播放器
└── Localizable.xcstrings        # 中英文文案（String Catalog）
M3U8 DownloaderTests/            # 单元测试
M3U8 DownloaderUITests/          # UI 测试
M3U8 Downloader.xcodeproj/       # objectVersion 77，源码目录自动同步
iOS-Info.plist                   # 仅 iphoneos / iphonesimulator 使用（macOS 走 GENERATE_INFOPLIST_FILE）
AGENTS.md                        # 代码风格与协作规则（必须遵守）
LICENSE                          # 上游 MIT
```

### 3.1 关键约定：新增 Swift 文件不需要改 pbxproj

工程使用 `PBXFileSystemSynchronizedRootGroup`（`objectVersion = 77`），三个同步根组分别是 `M3U8 Downloader`、`M3U8 DownloaderTests`、`M3U8 DownloaderUITests`。

- 在 `M3U8 Downloader/` 下新建 `.swift` 文件 → **自动加入 app target**。
- 测试文件**必须**放在 `M3U8 DownloaderTests/`，不能放进 app 目录（否则会被编进 app）。
- 只有新增 target、改动 Build Settings、新增资源目录例外项时，才需要手改 `project.pbxproj`。**尽量避免**：pbxproj 是手工维护的高风险区域。

### 3.2 并发与隔离模型

- `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`（app target）：**所有类型默认 `@MainActor`**。
- `SWIFT_APPROACHABLE_CONCURRENCY = YES`。
- 因此任何跨 actor 传递的数据（嗅探消息、下载请求）必须显式写成：
  ```swift
  nonisolated struct SniffedMedia: Sendable, Hashable { ... }
  ```
  项目里的既有范例：`DownloadSegment.swift` 之外的 `SegmentRequest` / `SegmentResult`（`Services/SegmentDownloader.swift`）、`HLSPlaylist` 系列（`Services/HLSPlaylist.swift`）、`MediaAssembler`。
- `@Observable` 类必须 `@MainActor`（`DownloadEngine`、`SettingsStore` 都是如此）。
- 禁止 `ObservableObject` / `@Published` / `@StateObject` / `@ObservedObject` / `@EnvironmentObject`；禁止 GCD（`DispatchQueue`）；用 `Task.sleep(for:)`。

### 3.3 iOS 与 macOS 的实质差异（CI 只覆盖 iOS）

| 能力 | iOS | macOS |
| --- | --- | --- |
| 组装结果 | 本地 `.m3u8` 播放列表（`MediaAssembler.assemble` 的 `#if os(iOS)` 分支），引用 `Segments/` | 合并成 `media.ts` / `media.mp4`，`AVAssetExportSession` 导出到用户指定路径 |
| `DownloadFileStore.finalMediaURL` | `taskDirectory/{outputFileName}.m3u8` | `destinationMP4URL` |
| 播放 | `VideoPlayerView` 启动 `LocalHLSServer`，`AVPlayerViewController` | 直接 `AVPlayerView` |
| 保存位置 | App 沙盒 `Documents/Downloads` | `NSSavePanel` 选择路径 + security-scoped bookmark |
| 主界面 | `NavigationSplitView` + `navigationDestination` | `NavigationSplitView` 三栏 + `Settings` scene |

**改动原则：只动 iOS 分支，不动 `#if os(macOS)` 分支**（除非必要）。CI 编译不到 macOS 分支，改了也没人验证，容易悄悄弄坏。如果不得不改 macOS 分支，保持语法最小化，并在 PR 描述里标注"macOS 分支未验证"。

> 注意：CI 的 `-destination 'generic/platform=iOS'` 只构建 iOS app target，macOS 分支的代码虽然不参与编译，但**必须保持语法正确**（同一份源文件，未来谁用 Xcode 打开 macOS scheme 会编译它）。

### 3.4 下载引擎调用链（你要挂钩的地方）

```
ContentView.task
  └─ DownloadEngine(modelContext:settings:mode:)        M3U8 Downloader/Services/DownloadEngine.swift:21
       addJob(sourceURLString:outputName:destinationURL:) DownloadEngine.swift:31
       start(_:)                                          DownloadEngine.swift:58
       run(jobID:)                                        DownloadEngine.swift:123
         ├─ prepare(_:)                                   DownloadEngine.swift:159
         │    session = URLSession(settings.makeURLSessionConfiguration())   :182
         │    fetchText(url:session:)                     :330  ← 需要加请求头
         │    parser.parseResolved(text:sourceURL:loader:) :184
         ├─ downloadSegments(_:)                          DownloadEngine.swift:240
         │    SegmentRequest(...)                         :272
         │    SegmentDownloader.download(_:)              Services/SegmentDownloader.swift:26
         │      fetchData(url:session:...)                :65   ← 需要加请求头
         │      decrypt(...) → 取 AES key 也走 fetchData  :91
         ├─ MediaAssembler.assemble(job:)                 :141
         └─ 写 finalFilePath / 状态                       :143
```

---

## 4. 缺口清单与实现方案（按 PR 顺序）

### PR 1：CI（见 §2）

### PR 2：工程清理（纯配置，风险低，先做）

1. **签名团队**：把 `project.pbxproj` 里全部 8 处 `DEVELOPMENT_TEAM = C2A3XCXCZS;` 换成用户自己的 Team ID，或者**直接删掉整行**（CI 是免签构建；Sideloadly 会重新签名，本地 Team ID 对 CI 无用）。
   - 行号（基线）：`308, 370, 396, 447, 497, 523, 548, 573`
2. **Bundle ID**：替换 `LSX-s-Software.M3U8-Downloader*`（共 6 处）。
   - 行号：`425, 476`（app）、`502, 528`（Tests）、`553, 578`（UITests）
   - 建议：app 用 `com.<自己的前缀>.Videosniffer` 之类的自有前缀；Tests / UITests 保持 app ID + `.Tests` / `.UITests` 后缀。**不要**沿用上游 ID，也不要猜测别人的 Team ID。
3. **显示名**：两处都要改，iOS 实际读取的是 plist：
   - `iOS-Info.plist` 的 `CFBundleDisplayName`（第 8 行）→ `VideoSniffer`
   - `project.pbxproj` 的 `INFOPLIST_KEY_CFBundleDisplayName = "M3U8 Downloader";`（`408`、`459` 行）→ `VideoSniffer`
4. **ATS**：`iOS-Info.plist` 第 27–31 行目前只有 `NSAllowsLocalNetworking`，不足以浏览任意 http 站点：
   ```xml
   <key>NSAppTransportSecurity</key>
   <dict>
       <key>NSAllowsArbitraryLoads</key>
       <true/>
       <key>NSAllowsLocalNetworking</key>
       <true/>
   </dict>
   ```
   个人自用、不上架，可以接受。该 plist 只用于 iphoneos / iphonesimulator SDK，不影响 macOS。
5. **可选**：加 `ITSAppUsesNonExemptEncryption = NO`（如果将来要通过别的方式分发）。非必需。

> 改 Bundle ID 会导致设备上已装版本被当成另一个 App；用户重装前应导出已下载文件。

### PR 3：浏览器（WKWebView + Tab 结构）

**插入点**：`M3U8 Downloader/ContentView.swift`

- `ContentView.body`（第 17 行）：iOS 改为两个 Tab：
  ```swift
  #if os(iOS)
  TabView {
      Tab(.browser, systemImage: "safari") { BrowserView(engine: engine) }
      Tab(.downloads, systemImage: "arrow.down.circle") { DownloadNavigationView(...) }
  }
  #else
  DownloadNavigationView(...)
  #endif
  ```
  注意 `Tab` 初始化器在 iOS 18+ / macOS 15+ 可用，我们用 `Tab(title:systemImage:content:)` 这种写法，不要用 `.tabItem()`（AGENTS.md 明确禁止）。
- `Downloads` Tab 需要保留设置入口。现有入口在 `Views/DownloadSidebarView.swift:27`（iOS toolbar 的 gear 按钮），它在新结构里仍然可达。**但 UI 测试默认打开的是第一个 Tab（Browser），`app.buttons["Settings"]` 会找不到** → 见 §5.3 处理。

**新建类型（每个类型一个文件）**：

- `M3U8 Downloader/Browser/BrowserViewModel.swift`
  ```swift
  @MainActor
  @Observable
  final class BrowserViewModel { ... }
  ```
  - 持有 `WKWebView`、`canGoBack` / `canGoForward` / `isLoading` / `currentURL` / `pageTitle`（用 KVO 或 `WKWebView` 的 `observation`；Swift 6 下建议用 `withObservationTracking` 或用 `WKWebView` 的 `KVO` 包装）。
  - `load(_ urlString: String)`：补全 scheme（用户只输入 `example.com` 时补 `https://`），拒绝非 http/https。
  - `goBack()` / `goForward()` / `reload()` / `stopLoading()`。
  - `handleNavigationAction`：`WKNavigationDelegate.decidePolicyFor` 里拒绝 `blob:` / `file:` 打开，其余放行。
  - **创建** `WKWebViewConfiguration`：`websiteDataStore = .default()`（保留 Cookie）；`allowsInlineMediaPlayback = true`；`mediaTypesRequiringUserActionForPlayback = []`（很多站点自动播放需要）；注入嗅探脚本（PR 4）。
- `M3U8 Downloader/Browser/BrowserView.swift`：`WKWebView` 的 `UIViewRepresentable`。iOS only（`#if os(iOS)`）。不要在 view 里塞业务逻辑，交互全部进 ViewModel。
- `M3U8 Downloader/Browser/BrowserURLBarView.swift`：地址栏（`TextField` + 进度指示 + 前进/后退/刷新/停止）。
- `M3U8 Downloader/Browser/BrowserSniffedMediaView.swift`：嗅探结果列表（每个候选：URL、类型、可选分辨率/码率、下载按钮）。

**行为约定**：

- 默认 URL 可以留空，或者给一个中性起始页（不要预填具体网站，避免隐私/合规争议）。
- 地址栏编辑态与导航态分开：用户点地址栏时全选，回车才 load。
- 不要用 `.sheet` 包整个浏览器；Tab 内直接展示。

### PR 4：嗅探（最大工作量）

**原理**：`NSURLProtocol` 拦截不到 WKWebView；`WKURLSchemeHandler` 只能处理自定义 scheme。**必须走 JS 注入 + `WKScriptMessageHandler`。**

**注入内容**（`WKUserScript`，`injectionTime: .atDocumentStart`，`forMainFrameOnly: false`，把同一段脚本注入所有 frame）：

1. hook `window.fetch`：包装原函数，`input` 是 Request 或字符串时取 URL。
2. hook `XMLHttpRequest.prototype.open`：记录 URL。
3. hook `HTMLMediaElement.prototype` 的 `src` setter（或用 `Object.defineProperty` 包装 `src` / `play` / `load`），并扫描 `document.querySelectorAll("video, source")` 的 `src` / `currentSrc`。
4. `MutationObserver` 监听 `document.documentElement` 子树：新增 `video` / `source` 节点时上报。
5. 上报函数：`window.webkit.messageHandlers.videoSniffer.postMessage({url, kind, pageURL})`。
   - 只上报 `http:` / `https:`。
   - 判定：URL path 以 `.m3u8` 结尾或含 `m3u8` 关键字 → `hls`；`.mp4` / `.m4s` / `.m4v` / `Content-Type` 不可见 → 按扩展名推断 `file`。
   - **不要**上报 `blob:` / `data:`（不可取回）；这类 MSE 播放的底层地址通常能在 fetch/XHR 里抓到 `.m3u8` 或 `.mp4`。
6. JS 里必须 try/catch 包住所有 hook，**不能因为注入脚本抛错而破坏页面**。
7. 上报前在 JS 侧用 `Set` 去重；Swift 侧再用 URL 去重（一个 URL 只保留一条）。

**Swift 侧**：

- `M3U8 Downloader/Browser/SniffMessageHandler.swift`：`@MainActor final class ... : NSObject, WKScriptMessageHandler`。
  - 校验 `message.name == "videoSniffer"`；
  - `message.body` 必须是 `[String: Any]`，字段缺失就丢弃，**不要 force unwrap**；
  - 限制字符串长度（如 URL > 4096 字符丢弃），防页面塞垃圾；
  - 把结果转成 `nonisolated struct SniffedMedia: Sendable, Hashable, Identifiable`（`id` 用 URL 字符串）交给 ViewModel；
  - **消息内容是不可信输入**：只当作 URL 数据，绝不 `eval`、绝不当指令执行。
- 注意 `WKScriptMessageHandler` 强引用循环：配置持有 handler，handler 回调里不要强捕获 `WKWebView` / ViewModel；用 `weak` 或把数据通过闭包交给 ViewModel。

**Cookie / Referer / UA 采集（PR 5 会用）**：

- `Referer` = `location.href`（JS 上报，或由 `WKWebView` 的 `WKNavigationAction.request` 取）。
- `User-Agent` = `navigator.userAgent`（JS 上报）。
- **Cookie 是坑**：`document.cookie` 拿不到 `HttpOnly` Cookie。可靠的来源是 `WKWebsiteDataStore.default().httpCookieStore.getAllCookies`，按候选 URL 的 host 域名做 `domainMatches` 过滤，拼成 `Cookie:` 头。建议用 `WKHTTPCookieStore` 而不是 JS。
- 如果自定义头和 Cookie 都拿不到，退路：把请求交给 WKWebView 自身的网络栈（但那样就没有下载进度和分片管理）。**不要**为了取 Cookie 去禁用网站的 HttpOnly 设置或绕过鉴权。

**去重与排序**：按发现时间倒序；同一 URL 只保留最新一条；`.m3u8` 与 `.mp4` 分区展示。

### PR 5：请求头透传（防盗链）

**数据模型**：`M3U8 Downloader/Models/DownloadJob.swift:30` 的 `init`，新增**全部可空、带默认值**的字段（SwiftData 轻量迁移需要）：

```swift
init(
    title: String, sourceURLString: String, outputFileName: String,
    destinationPath: String? = nil, destinationBookmark: Data? = nil,
    refererURLString: String? = nil,
    cookieHeader: String? = nil,
    userAgent: String? = nil,
    mediaKindRawValue: String? = nil
)
```

并新增属性 `var refererURLString: String?`、`var cookieHeader: String?`、`var userAgent: String?`、`var mediaKindRawValue: String?`。**不要给已有的非可选属性改类型或加无默认值的新存储属性。**

`addJob`（`DownloadEngine.swift:31`）新增一个重载或把参数做成带默认值的可选参数：

```swift
func addJob(
    sourceURLString: String,
    outputName: String,
    destinationURL: URL?,
    requestHeaders: [String: String] = [:],
    mediaKind: MediaKind = .hls,
    pageURLString: String? = nil
) throws
```

**传给分片下载**：`SegmentRequest`（`Services/SegmentDownloader.swift:4`）新增

```swift
var requestHeaders: [String: String] = [:]
```

必须是**带默认值**的字段，因为 `M3U8 DownloaderTests/M3U8_DownloaderTests.swift:43` 使用成员初始化器构造 `SegmentRequest`，加无默认值字段会直接编译失败。

`fetchData`（`SegmentDownloader.swift:65`）里：先设置 `requestHeaders`，再设置 `Range`（Range 头不能被覆盖）。`decrypt`（`:91`）取 AES key 时同样带上 `requestHeaders`。

`fetchText`（`DownloadEngine.swift:330`）改为：

```swift
private func fetchText(url: URL, session: URLSession, headers: [String: String]) async throws -> String {
    var request = URLRequest(url: url)
    headers.forEach { request.setValue($1, forHTTPHeaderField: $0) }
    let (data, response) = try await session.data(for: request)
    ...
}
```

`prepare`（`DownloadEngine.swift:159`）在 `:182` 建完 session 后，从 job 的字段拼出 headers，传给 `fetchText` 与 `parseResolved` 的 loader（`:184`）。

> **注意**：`URLSession` 默认会跟随重定向并携带请求头到新 host，可能把 Cookie 泄露给 CDN/第三方域。分片下载通常跨域（CDN），这是必须的；但 `Cookie` 头只应由用户明确下载的站点设置。保持简单：按候选 URL host 匹配后透传，不额外扩散。

### PR 6：直接下载 MP4

**判定**：嗅探结果 `mediaKind == .file` 时走直链下载，不进 `HLSPlaylistParser`。

**实现路径**（最小改动、不影响既有 HLS 流程）：

1. `prepare(_:)`（`DownloadEngine.swift:159`）开头分支：
   ```swift
   if job.mediaKind == .progressive {
       try await prepareProgressive(job)   // 创建 1 条 DownloadSegment，index 0
       return
   }
   ```
2. `prepareProgressive`：判断 Content-Length（`HEAD` 或 `URLSession.download` 的 delegate），从 URL path 或 `Content-Type` 推断扩展名（默认 `.mp4`），把目标文件名写到 `job.outputFileName`（保留扩展名，`String+FileName.swift` 里已有清洗逻辑）。
3. 新建 `M3U8 Downloader/Services/ProgressiveFileDownloader.swift`：
   ```swift
   nonisolated struct ProgressiveDownloadRequest: Sendable { ... }
   nonisolated final class ProgressiveFileDownloader: NSObject, URLSessionDownloadDelegate, @unchecked Sendable { ... }
   ```
   用 `URLSessionDownloadTask` + delegate 更新进度（`Progress` / 已下载字节），最终 `moveItem` 到 `taskDirectory/{outputFileName}.mp4`。
   若用 `@unchecked Sendable`，必须像 `LocalHLSServer` 那样用 `NSLock` 包住可变状态，不要裸共享。
4. 完成后**不要**调用 `MediaAssembler`：直接
   ```swift
   job.finalFilePath = fileURL.path(percentEncoded: false)
   job.completedAt = Date()
   job.status = .completed
   ```
5. **播放兼容性**：`VideoPlayerView`（`Views/VideoPlayerView.swift:56`）在 iOS 上对非 `.m3u8` 文件直接 `return fileURL`，所以 `.mp4` 可直接用 `AVPlayer` 播放，无需改播放器。
6. **进度计算坑**：`DownloadEngine.recalculateProgress`（`DownloadEngine.swift:341`）只统计 `job.segments`；`downloadedBytes` 是 `segments.reduce`。直链路径必须维护那 1 条 segment 的 `byteCount`，否则进度恒为 0。或者在该函数里加 `if job.mediaKind == .progressive` 分支直接用 `job.downloadedBytes`。**两者都行，但要一致。**

**不做的**：不实现 m3u8 合并成单个 mp4（iOS 上游行为就是 `.m3u8` + `Segments/`，播放由 `LocalHLSServer` 支撑）。不在 iOS 上跑 `AVAssetExportSession` 合并（跨平台差异大，且非必需）。

### PR 7：界面文案（Localizable.xcstrings）

现有 key 全是 `"extractionState": "manual"` 的符号 key，中英双语都已翻译，例如 `.downloads`、`.settings`、`.addDownload`、`.m3U8Url`、`.downloadM3U8Media`。

新增时：

- 使用符号 key（代码里写 `.browser`、`Text(.browser)`），**不要**用字面量字符串。
- 每个新 key 同时给 `en` 与 `zh-Hans`，两个都是 `"state": "translated"`。
- `"extractionState": "manual"`。
- 建议新增 key（按需，不要硬塞）：
  `browser`、`browseURL`、`enterAWebsiteURL`、`goBack`、`goForward`、`reload`、`stop`、`sniffedVideos`、`noVideosFound`、`downloadThisVideo`、`addToDownloads`、`videoTypeHLS`、`videoTypeFile`、`openInBrowser`、`loading`、`failedToParseURL`、`httpOnlyCookieNotAvailable`（如果展示限制说明）。

修改 `Localizable.xcstrings` 后可以用 `jq` 做一次 JSON 校验（在 Linux 上能跑）：

```bash
jq empty "M3U8 Downloader/Localizable.xcstrings"
```

### PR 8：UI 测试与验收

- 新增浏览器 / 嗅探相关 UI 测试时，**只用稳定的 accessibility identifier**，不要依赖抓取 URL 的文本。
- UI 测试不能依赖外网页面（网络抖动会 flaky）。只测"结构"：Tab 能切换、地址栏能输入、设置能打开。
- 如果要测嗅探，在 Demo 模式下预置 `PreviewSamples` 里的假嗅探结果（`Utilities/PreviewSamples.swift` 目前只有下载示例，可扩展）。

---

## 5. 陷阱清单（踩了就浪费一次 CI）

### 5.1 `SegmentRequest` 的成员初始化器

`M3U8 DownloaderTests/M3U8_DownloaderTests.swift:43` 直接调用 `SegmentRequest(id:index:urlString:outputURL:retryLimit:encryptionMethod:keyURLString:initializationVectorHex:byteRangeLength:byteRangeOffset:)`。

→ **任何新增字段都必须带默认值**，否则测试 target 编译失败（app 编译通过、测试编译失败，CI 的 build job 可能看不出来）。

### 5.2 `DownloadJob.init` 的调用方

`DownloadEngine.addJob`（`:46`）与 `PreviewSamples.swift`、测试都可能构造 `DownloadJob`。

→ 新参数全部带默认值；不改既有参数顺序。不允许把已有属性改成非可选。

### 5.3 "Settings" 按钮与 UI 测试

`M3U8 DownloaderUITests/M3U8_DownloaderUITests.swift:31`：

```swift
app.buttons["Settings"].click()
```

它依赖 `Views/DownloadSidebarView.swift:27` 那个 gear 按钮，并且**默认落地的界面必须是下载页**。

改成 TabView 后默认落在 Browser 页，该测试会失败。三个处理方式（选一个）：

- **推荐**：改 UI 测试，先切到 Downloads Tab（用 Tab 的 label "Downloads" / 中文文案），再点 Settings。注意设备语言可能是英文，使用 `.accessibilityIdentifier("downloadsTab")` 更稳。
- 或者在 Browser 工具栏也放一个 Settings 入口（不自然，不推荐）。
- 或者把 Browser 作为第二个 Tab、Downloads 作为第一个 Tab（会改变用户主界面预期，不推荐）。

### 5.4 `Info.plist` 是按 SDK 生效的

`project.pbxproj` 里：

```
GENERATE_INFOPLIST_FILE = YES;
"GENERATE_INFOPLIST_FILE[sdk=iphoneos*]" = NO;
"GENERATE_INFOPLIST_FILE[sdk=iphonesimulator*]" = NO;
"INFOPLIST_FILE[sdk=iphoneos*]" = "iOS-Info.plist";
"INFOPLIST_FILE[sdk=iphonesimulator*]" = "iOS-Info.plist";
```

→ 改 `iOS-Info.plist` 只影响 iOS；macOS 使用生成式 plist。因此 ATS、显示名改在这里是对的。

### 5.5 测试文件的位置

放在 `M3U8 DownloaderTests/`。放在 `M3U8 Downloader/` 下会被自动编进 app（同步根组会无条件收集）。

### 5.6 `#if os(macOS)` 的代码 CI 看不到

`AVAssetExportSession`、`NSSavePanel`、`NSWorkspace`、`Settings` scene、`defaultSize` 等分支在 iOS 构建中**不参与编译**，语法错误也发现不了。改动时格外保守。

### 5.7 强制解包与强制 `try`

AGENTS.md 禁止。已有测试文件里有两处历史 `URL(...)!`（`M3U8_DownloaderTests.swift:496/517`），**不要模仿、也不要顺手扩散**。

- **单元测试用 Swift Testing**（`import Testing`、`@Test`、`#expect`、`#require`），不是 XCTest。新测试照此写，用 `try #require(...)` 取 URL。
- **UI 测试用 XCTest**（`import XCTest`、`XCUIApplication`），沿用 `M3U8 DownloaderUITests/` 的现有风格。

### 5.8 并发标注

- 新 DTO：`nonisolated struct ... : Sendable`。
- 新 delegate / NSObject 子类若跨线程：`@MainActor`（如果只在主线程回调）或 `@unchecked Sendable` + `NSLock`（如果 URLSession delegate 在其他队列）。
- `WKScriptMessageHandler` 回调在主线程，标记 `@MainActor` 即可。

### 5.9 依赖

**不要引入第三方库**（AGENTS.md：先问；用户明确要求零依赖）。JS 用内联字符串，不引第三方嗅探库。不要为了图省事加 Swift Package。

### 5.10 敏感信息

**任何密钥、证书、Apple ID、Cookie、token 都不能进仓库**。嗅探日志也不要打印完整 Cookie / Authorization 头（调试时也要注意）。

---

## 6. 验收标准（用户会按这个试）

在 Windows 上用 Sideloadly 安装每次 CI 产出的 IPA 后：

1. 打开 App，看到 **浏览 / 下载** 两个 Tab。
2. 浏览器：输入任意可用网址 → 能访问；前进 / 后退 / 刷新 / 停止 正常；地址栏显示当前 URL 与加载状态。
3. 访问一个使用 HLS 的公开站点（例如公开的 m3u8 测试页）→ 嗅探列表出现至少一条 `.m3u8`，分辨率/码率提示（若可拿到）。
4. 点击下载 → 出现在下载列表 → 下载进度增长 → 可暂停 / 继续 / 取消 → 完成后在详情页能播放。
5. 访问一个防盗链站点（需要 Referer / Cookie 的）→ 下载不返回 403。
6. 直接 MP4：嗅探到 `.mp4` 候选 → 下载完成后可播放。
7. 设置面板仍可打开（从下载页）、代理 / 并发 / 超时设置仍生效。
8. `Demo` 模式仍可用（`--demo-mode`）。
9. 切换系统深色模式，界面正常；中英文都无缺失文案。

---

## 7. 约束与合规（不可违反）

- **仅个人使用**，**不上架 App Store**、不做分发。
- 只处理**非 DRM** 内容与 HLS 明文密钥（AES-128）。**绝不实现 FairPlay / Widevine 绕过、绝不破解加密媒体**。
- **不得**使用上游签名团队 `C2A3XCXCZS` 或 Bundle ID `LSX-s-Software.M3U8-Downloader*`。Sideloadly 用**一次性免费 Apple ID** 重签。
- 仓库中**永不存放密钥、证书、Apple ID、密码、Cookie**。
- 不引入第三方框架（除非用户明确同意）。
- 上游 MIT 版权声明（`LICENSE`、`README.md`、`README.en.md`）必须保留。
- 下载内容的版权与站点 ToS 由用户自行承担；不要添加"绕过登录 / 绕过付费墙"功能。

---

## 8. 建议的第一个消息

接手后按这个顺序做，不要一次改太多：

1. 读 `AGENTS.md`（99 行，全部规则）。
2. 建 `.github/workflows/build.yml`，推分支，**先确认能产出 IPA**（此时源码未改，应该直接成功）。
3. 做 PR 2（工程清理），再跑一次 CI。
4. 做 PR 3 + PR 4（浏览器 + 嗅探），一次 CI；用户安装实测后反馈。
5. 做 PR 5 + PR 6（透传 + 直链 MP4）。
6. 最后补文案与 UI 测试、更新 README 状态表（把 ⬜ 改成 ✅）。

每一步 PR 描述里写清楚：改了什么、CI 链接、未验证的 macOS 分支、需要用户手动测试的点。
