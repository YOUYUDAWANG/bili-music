# BiliMusic

个人自用的 iOS 音乐 App:把 B 站当曲库,体验对标 YouTube Music。仅供学习,勿分发。

功能:搜索播放、后台/锁屏控制、电台连播(相关推荐)、收藏夹当歌单、个性化推荐、整曲缓存离线播放、音质选择、扫码登录。

## 构建

```bash
brew install xcodegen
xcodegen generate          # 由 project.yml 生成 BiliMusic.xcodeproj(不入库)
open BiliMusic.xcodeproj   # Xcode 选真机 ⌘R;免费账号签名 7 天,用 AltStore 续
```

架构与接口文档见 [ARCHITECTURE.md](ARCHITECTURE.md);`scripts/` 是接口验证脚本(Python,无依赖)。
