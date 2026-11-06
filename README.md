# M3U8 Downloader

![Swift](https://img.shields.io/badge/Swift-6-orange?style=flat&logo=swift) ![SwiftUI](https://img.shields.io/badge/framework-SwiftUI-blue?style=flat) ![Platforms](https://img.shields.io/badge/platforms-iOS%20%7C%20iPadOS%20%7C%20macOS-lightgrey?style=flat) ![Native](https://img.shields.io/badge/100%25-native-brightgreen)

简体中文 | [English](README.en.md)

M3U8 Downloader 是一个使用 SwiftUI 完全原生开发的跨平台 HLS 下载器，支持在 macOS 和 iOS 上添加 `.m3u8` 链接、下载分片、跟踪进度，并在下载完成后播放本地媒体文件

![M3U8 Downloader demo](Docs/demo.png)

## 产品优势

- 完全原生 Apple 平台开发，界面与系统体验一致
- 未使用任何第三方库，依赖关系清晰可控
- 软件体积仅 3.5 MB，轻量直接

## 功能

- 解析 M3U8 主播放列表和变体播放列表
- 并发下载 TS 分片，支持暂停、继续、重试、取消和删除
- 支持 AES-128 加密分片和 byte range 分片下载
- 下载完成后组装为本地 MP4 文件
- 在详情页展示任务状态、分片进度、已下载大小、创建时间和完成时间
- 支持本地播放已下载媒体
- 提供下载并发数、重试次数和超时时间设置
- 支持 HTTP / HTTPS / SOCKS 代理
- 提供简体中文和英文
- 深色模式

## 运行要求

- iOS / iPadOS 18.0 或更新版本
- macOS 26.0 或更新版本

## 开发

### 系统要求

- Xcode 26 或更新版本
- Swift 6 或更新版本
- iOS / iPadOS / macOS SDK

### 技术栈

- SwiftUI
- SwiftData
- Swift Observation (`@Observable`)
- Swift Concurrency (`async` / `await`)
- URLSession
- AVKit

项目完全基于 Apple 原生框架开发，未引入任何第三方库

### Demo Mode

工程包含 `M3U8 Downloader Demo` scheme，用于加载内存中的示例下载任务，方便预览列表、详情和状态展示。也可以用启动参数或环境变量开启 demo mode：

```sh
--demo-mode
```

```sh
M3U8_DOWNLOADER_DEMO_MODE=1
```

### 项目结构

```text
M3U8 Downloader/
├── Models/        SwiftData models for download jobs and segments
├── Services/      HLS parsing, segment download, assembly, storage and playback services
├── Settings/      Download, proxy and persistent settings
├── Utilities/     Shared helpers for paths, keychain, security scope and demo launch mode
└── Views/         SwiftUI views for list, detail, settings and download actions
```
