# Bilibili Music — 架构文档

个人自用的 iOS 音乐 App,把 B 站当曲库,UI 与交互气质向 Apple Music 看齐。
只做:听歌、本地缓存、搜索、推荐、收藏夹同步、歌词、音乐/MV 切换。不做:弹幕、评论、上架。

## 约束与决策

| 决策 | 选择 | 原因 |
|---|---|---|
| 平台 | iOS 17+, SwiftUI, Swift 5.10+ | 单人开发,最新 API 省代码 |
| 安装方式 | 免费开发者账号 + AltStore 自动续签 | 无付费账号,7 天签名靠 AltStore 续 |
| 架构 | 单 Module,MVVM,`@Observable` | 自用 app,不做分层框架 |
| 数据库 | JSON 索引文件(P4 实测够用) | 缓存索引单表,JSON 最简;等 P5 歌单需要关系模型再考虑 SwiftData |
| 网络 | URLSession + async/await,无第三方依赖 | 接口都是简单 GET + JSON |
| 播放 | AVPlayer + AVURLAsset(自定义 header) | DASH m4a 直接播,验证已通 |

## 数据源(全部已用脚本验证,见 scripts/)

所有请求必须带 header:`Referer: https://www.bilibili.com` + 浏览器 UA,否则 CDN 403。
登录态 = Cookie(核心是 SESSDATA),扫码登录获取,存 Keychain。

| 功能 | 接口 | 签名 | 登录 |
|---|---|---|---|
| 视频信息/分P | `/x/web-interface/view?bvid=` | 无 | 否 |
| 音频流地址 | `/x/player/playurl?bvid=&cid=&fnval=16` | 无 | 高码率/Hi-Res 需要 |
| MV 视频流 | `/x/player/playurl?bvid=&cid=&qn=64&fnval=0` | 无 | 部分内容需要 |
| 字幕/歌词 | `/x/player/v2?bvid=&cid=` + 字幕 JSON URL | 无 | 部分字幕需要 |
| 搜索 | `/x/web-interface/wbi/search/type` | WBI | 否 |
| 首页推荐 | `/x/web-interface/wbi/index/top/feed/rcmd` | WBI | 个性化需要 |
| 相关推荐(电台) | `/x/web-interface/archive/related?bvid=` | 无 | 否 |
| 收藏夹列表/内容 | `/x/v3/fav/folder/created/list-all`, `/x/v3/fav/resource/list` | 无 | 是 |
| 扫码登录 | `/x/passport-login/web/qrcode/generate` + `poll` | 无 | — |

接口细节均参考 [bilibili-API-collect](https://github.com/SocialSisterYi/bilibili-API-collect)。

### 关键事实(脚本验证得出)

- 音频/MV 流 URL 有时效(~2h),**只能持久化 BV/cid,播放时现取 URL**
- DASH audio id:30216=64K / 30232=132K / 30280=192K / 30251=Hi-Res(flac 字段,大多为 null,需按可选解析)
- 未登录也能拿到 192K,Hi-Res/杜比需大会员 Cookie
- 歌词优先使用 B 站字幕文件;很多投稿没有字幕,需要在 UI 里显示空状态
- MV 模式优先取单文件 MP4,目标是稳定播放和快速切换,不追求最高画质
- WBI 签名:nav 接口取 img/sub key → 64 位重排表取前 32 位 → 参数按 key 排序 + wts 时间戳 + MD5。mixin key 缓存一天即可
- 相关推荐接口效果好,适合做自动连播;首页推荐未登录是泛化内容,需登录 + 按分区/时长过滤才像音乐推荐

## 模块划分

```
BiliMusic/
├── App/              入口、全局环境
├── API/              BiliClient(URLSession 封装)、WBISigner、各接口的请求/响应模型
├── Auth/             扫码登录、Cookie 管理(Keychain)
├── Player/           PlayerEngine(AVPlayer 封装)、PlayQueue、NowPlaying(锁屏/控制中心)
├── Cache/            CacheStore(JSON 索引)、DownloadManager、本地文件(Documents/audio/{bvid}_{cid}.m4a)
├── Design/           AppTheme(Apple Music 红 accent + 系统背景)
└── Features/         各页面 View + ViewModel
    ├── Home/         音乐发现(相关推荐/缓存种子/关键词兜底,经 MusicFilter)
    ├── Search/
    ├── Favorites/    收藏夹 + FavoriteManager(短按默认夹/长按选夹)
    ├── Player/       正在播放页(含歌词、音乐/MV 切换)+ mini bar
    └── Library/      缓存管理
```

### 核心模型

无 SwiftData/ORM。曲目是普通 `struct Track`;缓存索引是 `CachedEntry` 的 JSON 文件
(`CacheStore`),播放队列在 `PlayerEngine` 内存里,收藏夹直接用 B 站的。

```swift
struct Track       // bvid, cid, title, artist(UP主), coverURL, duration, ownerMid
struct CachedEntry // bvid, cid, 元信息, 本地文件名, 音质 id, 文件大小, 下载时间
```

### 播放链路

```
Track(bvid, cid)
  → CachedAudio 存在? → 本地文件 URL
  → 否则 playurl 现取流 URL → AVURLAsset(options: [AVURLAssetHTTPHeaderFieldsKey: headers])
  → AVPlayer
播完 → PlayQueue 下一首;队列空且开了电台模式 → related 接口取下一首(按时长 1~10min 过滤)
```

后台播放:Audio background mode + `MPNowPlayingInfoCenter`(标题/封面/进度)+ `MPRemoteCommandCenter`(播放暂停/上下首/拖进度)。

### 缓存策略

- 整曲下载(不做边播边缓存):playurl 取最高音质 → URLSession downloadTask → 移入 Documents/audio/
- 手动下载 + 可选"自动缓存播放过的曲目"开关
- 缓存管理页:按大小排序、单删、清空

## 路线图

- [x] **P1 验证**:playurl 链路、WBI 搜索、推荐接口(scripts/ 两个脚本)
- [x] **P2 最小可播**:Xcode 工程(xcodegen)、粘贴 BV 号播放、后台播放 + 锁屏控制,真机验证通过(2026-06-12)
- [x] **P3 可用**:扫码登录、搜索页、播放队列 + 正在播放页、相关推荐自动连播(电台)。真机验证:扫码登录、搜索播放、锁屏播放/控制均稳定
- [x] **P4 缓存**:整曲下载(带进度)、自动缓存开关、缓存优先播放(离线可用)、缓存管理页(删除/清空/占用)。模拟器验证:自动缓存落盘 + 索引正确、重启后走本地文件播放
- [x] **P5 推荐与收藏**:收藏 tab(收藏夹→歌单,分页、过滤失效稿件)、推荐 tab(推荐流按时长 1~11 分钟过滤,换一批);另修复下载慢(改 URLSessionDownloadTask,3MB 约 1~2 秒)、新增音质选择(设置页,同时作用于播放与下载,缓存条目记录音质)。真机验证:本地缓存与离线播放稳定
- [~] **P6 打磨**:已实现并通过模拟器构建 — UI 向 Apple Music 看齐(AppTheme 红 accent + grouped 列表)、队列管理、收藏(短按默认夹/长按选夹)、在线歌词(LRCLIB+B站字幕兜底)、音乐/MV 切换、Wi-Fi 优先 MV、音乐内容过滤(MusicFilter)、预取提速。**待真机验证**:歌词匹配质量、MV 切换与后台、收藏写入、UP 合集。未做:历史记录、定时关闭、错误提示打磨、缓存搜索/排序。详见 [TODO.md](TODO.md)。CarPlay 不做(用户明确不需要)

## 风险

| 风险 | 应对 |
|---|---|
| B 站接口变动/风控(-352 等) | 接口层集中在 API/ 一处;header 模拟浏览器;失败时降级提示 |
| AVPlayer 播 DASH 流的兼容性 | P2 第一件事验证;不行则降级为"先下后播" |
| 免费签名 7 天过期 | AltStore 自动续签;数据在 Documents 不受重签影响 |
| Cookie 过期 | 检测 -101 响应码,引导重新扫码 |
