---
type: project_topic
status: active
summary: "记录包含本地 Swift Package 时的 iOS CI 编译约束。"
tags: [ci, xcode, swift-package, build]
contains: [decision, lesson]
created: "2026-08-14"
updated: "2026-08-14"
related: [".github/workflows/build.yml", "project.yml", "Vendor/README.md"]
authoring_mode: ai_generated
---
# iOS CI 编译

## 当前结论

- CI 使用 `BiliMusic` shared scheme 和 `generic/platform=iOS Simulator` 构建，不使用 `-target BiliMusic`，也不强制单一 `x86_64` 架构。
- `Vendor/**` 属于应用编译输入，修改该目录必须触发 CI。
- CI 继续关闭代码签名；XcodeGen 生成工程后再执行 scheme 构建。

## 经验与教训

- 对含多层本地 Swift Package 的 XcodeGen 工程使用 `xcodebuild -target`，可能让各 Package 使用分离的 build root，导致依赖方查找错误目录下的 generated module map。
- 此故障最早表现为 `LNSystemMarqueeLabel.modulemap not found`；随后出现的 `_DarwinFoundation2/3` 缺失属于依赖扫描连锁错误，不应误判为业务源码或单纯的 x86_64 不兼容。
- shared scheme 会建立统一 Package 依赖图；本地 Xcode 27 Beta 的 generic simulator 构建同时覆盖 arm64 与 x86_64 并通过，GitHub Actions 的 Xcode 26.3 编译门禁也已通过。
