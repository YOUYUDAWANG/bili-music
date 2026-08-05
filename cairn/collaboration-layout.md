---
type: project_topic
status: active
summary: "Bilibili Music 采用 CLAUDE.md 主本、AGENTS.md 跨代理入口的 Claude-first 协作布局。"
tags: [project-cairn, collaboration, claude-code]
contains: [decision]
created: "2026-08-05"
updated: "2026-08-05"
related: ["CLAUDE.md", "AGENTS.md", ".cairn/config.yaml"]
authoring_mode: ai_generated
---
# Claude-first 协作布局

## 背景

Project Cairn 默认以根目录 `AGENTS.md` 作为规则与导航主本，并让 `CLAUDE.md` 引用它。本项目已有一份由 Claude 使用的完整架构文档，用户明确要求继续以 `CLAUDE.md` 为主本，不接受把它替换为单行引用或另行归档。

## 当前结论

- 根目录 `CLAUDE.md` 是项目规则、Cairn 导航与架构信息的主本。
- 根目录 `AGENTS.md` 保持精简，负责让 Codex 等其他代理在实质工作前读取 `CLAUDE.md`。
- `.cairn/config.yaml` 仍是 machine-readable Cairn 配置的唯一真相来源。
- 这是用户确认的项目级适配；标准 Cairn 审计若提示 `CLAUDE.md` 不是 `@AGENTS.md` 单行 stub，应将其视为已知、有意的布局差异，而不是自动覆盖主本。

## 决策记录

- 2026-08-05：初始化 Project Cairn 时确认采用 Claude-first 布局，并将原 `AGENTS.md` 中仍有效的 planning、CodeGraph、GSD 与 Git 安全规则合并到 `CLAUDE.md`。
