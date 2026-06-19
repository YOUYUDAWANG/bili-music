## 改动说明
<!-- 这个 PR 做了什么、为什么这么做 -->

## 关联 Issue
<!-- 例如：Closes #12 -->

## 自测情况
- [ ] 本地 `xcodegen generate` 后能编译通过
- [ ] 真机验证过（说明测了哪些场景）：
- [ ] 涉及 UI 改动（附截图）：

## 检查项
- [ ] 没有把 Cookie / SESSDATA / 个人密钥提交进来
- [ ] 配置改动改在 `project.yml`，而不是 Xcode 界面（界面改动会被 `xcodegen generate` 覆盖）
- [ ] 新增了 Swift 文件的话，已确认 `xcodegen generate` 能正确纳入
