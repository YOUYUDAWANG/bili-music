# BiliMusic LDDC Lyrics Backend

私有逐字歌词聚合服务。它把 LDDC 的 QQ QRC、酷狗 KRC、网易云 YRC
能力封装为受 Bearer 保护的 HTTP API；不包含桌面 GUI，也不负责决定
翻唱/原唱能否直接跟随播放。最终版本与时长门禁仍由 iOS App 执行。

## 边界

- 本目录是独立的 GPL-3.0-only 服务；不要把其中代码复制或链接进 Swift App。
- 只读取歌词平台；没有上传、收藏或账号写入。
- 单次请求最多同时查询三家来源，总超时默认 18 秒；失败不在 HTTP 层循环重连。
- 只缓存成功结果 24 小时。不得记录 Bearer、Cookie 或歌词请求正文；运行日志只保留来源 IP、HTTP 状态、候选数量、逐字数量和缓存命中。
- QQ、酷狗、网易云接口均为非官方依赖，必须保留 App 的现有直连和本机对齐回退。

## 本地启动

```bash
cd services/lddc-lyrics-backend
python3.12 -m venv .venv
.venv/bin/pip install -e '.[dev]'
export LDDC_BACKEND_TOKEN='replace-with-a-long-random-token'
.venv/bin/bilimusic-lddc-backend
```

或使用 Docker：

```bash
docker build -t bilimusic-lddc-backend .
docker run --rm -p 8788:8788 \
  -e LDDC_BACKEND_TOKEN='replace-with-a-long-random-token' \
  bilimusic-lddc-backend
```

## API

`GET /health` 不返回敏感信息。

`POST /v1/lyrics/resolve`：

```json
{
  "schema": "bilimusic-lddc-lyrics-v1",
  "requestID": "BV1...:123:cover",
  "title": "心拍数#0822",
  "artists": ["鹿乃"],
  "aliases": ["心拍数♯0822"],
  "durationMilliseconds": 322000,
  "requireDurationMatch": true,
  "maxCandidates": 6
}
```

请求必须携带 `Authorization: Bearer <LDDC_BACKEND_TOKEN>`。响应返回经过
歌名、歌手和可选 4 秒时长门禁的候选，以及标准化的行/字毫秒时间轴。
App 自动匹配与手动搜索都可调用该端点；手动列表只把已通过
服务和 App 二次校验的逐字词标记为「逐字」并在同版本内优先排序。

## App 配置

在 `Local.xcconfig` 设置：

```text
BILIMUSIC_LDDC_LYRICS_API_URL = http:/$()/your-host:8788
BILIMUSIC_LDDC_LYRICS_API_KEY =
```

令牌放入 macOS 钥匙串，由构建脚本注入：

```bash
security add-generic-password -U \
  -a BiliMusic \
  -s com.youyudawang.BiliMusic.lddc-lyrics-api \
  -w 'replace-with-the-same-token'
```

## macOS 常驻部署

`scripts/start_macos.sh` 从部署根目录的 `server-token.txt` 读取 Bearer；
`scripts/install_macos.sh` 创建用户级 LaunchAgent，并把日志写到
`~/Library/Logs/BiliMusic/`。Token 不进入 plist、源码包或日志。
当前自用部署只绑定 Mac mini 的 Tailscale 地址与 TCP 8788，不开放公网端口。

```bash
scripts/install_macos.sh \
  "$HOME/Library/Application Support/BiliMusic/LDDCLyricsBackend" \
  100.108.23.60 \
  8788
```

## 验证

```bash
.venv/bin/pytest -q
```
