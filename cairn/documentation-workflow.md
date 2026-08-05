---
type: project_topic
status: active
summary: "项目文档保存在 docs/，通过 XcodeGen fileGroups 提供 Xcode 导航，但不加入构建 target。"
tags: [documentation, xcode, xcodegen]
contains: [decision, procedure]
created: "2026-08-06"
updated: "2026-08-06"
related: ["project.yml", "CLAUDE.md", "docs/swift-for-java-cheatsheet.md"]
authoring_mode: ai_generated
---
# 项目文档工作流

## 当前结论

- 与 Bilibili Music 源码和协作直接相关的文档保存在仓库 `docs/`，并纳入 Git。
- `docs/` 通过 `project.yml` 的顶层 `fileGroups` 显示在 Xcode Project Navigator，只提供导航和阅读，不加入任何 target 或 App bundle。
- 跨项目或纯个人知识更适合沉淀到 Obsidian；不要为了在 Xcode 中可见而把个人知识机械复制进仓库。

## 实践指南

1. 在 `docs/` 中创建或修订项目文档，并确保相对链接从文档自身目录出发可以解析。
2. 只在 `project.yml` 中维护文件组，不在生成的 `.xcodeproj` 中手工添加文档。
3. 修改 `project.yml` 后运行 `xcodegen generate`。
4. 验证文档存在于 PBX group，但没有对应 PBX build file 或 target membership。
