# Bilibili Music 跨代理入口

> 本项目使用 Project Cairn 管理协作知识。用户明确选择 Claude-first 布局：根目录 `CLAUDE.md` 是项目规则与架构主本，`AGENTS.md` 只作为其他代理的入口。

## 必须读取

1. 在规划或修改项目前，完整读取根目录 `CLAUDE.md`；项目内同层文档发生规则冲突时以它为准，不改变系统、开发者或当前用户指令的优先级。
2. 按 `CLAUDE.md` 中的阅读顺序使用 `.planning/`、`cairn/ROADMAP.md`、`cairn/LOG.md` 和知识专题文档。
3. 机器可读的 Cairn 配置以 `.cairn/config.yaml` 为准。

## Cairn 门禁

- 完整读取并执行 `CLAUDE.md` 的“知识沉淀规则”，包括 Cairn 完成回复门禁及只读/不编辑例外。

## Cloud Agent

云端代理跑在 Linux 上，没有 Xcode，不能执行 `xcodegen`、`xcodebuild` 或 iOS 模拟器。仓库里能直接跑通的检查是标准库脚本：

```bash
python3 scripts/verify_search_rcmd.py "周杰伦 晴天"
```

`scripts/verify_audio.py` 走的 `view` 接口在云端 IP 上可能返回 HTTP 412。同一网络下 `pagelist` 和 `playurl` 仍能拿到音频流。完整 iOS 编译以 `.github/workflows/build.yml` 的 `macos-15` 门禁为准。
