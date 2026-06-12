#!/usr/bin/env python3
"""验证 B 站音频链路: BV号 -> 视频信息(cid) -> playurl DASH 音频流 -> 下载试听文件。

用法:
    python3 verify_audio.py BV1GJ411x7h7
    python3 verify_audio.py BV1GJ411x7h7 --cookie "SESSDATA=xxx"   # 登录后可拿高码率

只用标准库,无需 pip install。
"""

import json
import sys
import urllib.request
from pathlib import Path

HEADERS = {
    "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
                  "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36",
    "Referer": "https://www.bilibili.com",
}

AUDIO_QUALITY_NAMES = {
    30216: "64K",
    30232: "132K",
    30280: "192K",
    30250: "杜比全景声",
    30251: "Hi-Res 无损",
}


def api_get(url: str, cookie: str | None = None) -> dict:
    headers = dict(HEADERS)
    if cookie:
        headers["Cookie"] = cookie
    req = urllib.request.Request(url, headers=headers)
    with urllib.request.urlopen(req, timeout=15) as resp:
        data = json.loads(resp.read().decode())
    if data.get("code") != 0:
        raise RuntimeError(f"API 错误 code={data.get('code')}: {data.get('message')}")
    return data["data"]


def main() -> None:
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(1)
    bvid = sys.argv[1]
    cookie = None
    if "--cookie" in sys.argv:
        cookie = sys.argv[sys.argv.index("--cookie") + 1]

    # 1. 视频信息 -> cid (取第一个分P)
    print(f"[1/3] 获取视频信息: {bvid}")
    info = api_get(f"https://api.bilibili.com/x/web-interface/view?bvid={bvid}", cookie)
    print(f"  标题: {info['title']}")
    print(f"  UP主: {info['owner']['name']}")
    pages = info["pages"]
    print(f"  分P数: {len(pages)}")
    cid = pages[0]["cid"]
    print(f"  使用分P 1, cid={cid}")

    # 2. playurl 拿 DASH 音频流
    print("[2/3] 获取播放地址 (DASH)")
    play = api_get(
        f"https://api.bilibili.com/x/player/playurl?bvid={bvid}&cid={cid}"
        f"&fnval=16&fourk=1", cookie)
    dash = play.get("dash")
    if not dash or not dash.get("audio"):
        raise RuntimeError("没有 DASH 音频流(可能是充电专属/地区限制视频)")
    audios = sorted(dash["audio"], key=lambda a: a["id"], reverse=True)
    flac = (dash.get("flac") or {}).get("audio")
    if flac:
        audios.insert(0, flac)
    print("  可用音频流:")
    for a in audios:
        name = AUDIO_QUALITY_NAMES.get(a["id"], str(a["id"]))
        print(f"    - id={a['id']} ({name}) bandwidth={a['bandwidth']}")
    best = audios[0]
    url = best["baseUrl"]
    print(f"  选用最高音质: {AUDIO_QUALITY_NAMES.get(best['id'], best['id'])}")

    # 3. 带 Referer 下载,验证 CDN 不 403
    print("[3/3] 下载音频流...")
    out = Path(__file__).parent / f"{bvid}.m4a"
    req = urllib.request.Request(url, headers=HEADERS)
    with urllib.request.urlopen(req, timeout=60) as resp, open(out, "wb") as f:
        total = 0
        while chunk := resp.read(1 << 16):
            f.write(chunk)
            total += len(chunk)
    print(f"  完成: {out} ({total / 1024 / 1024:.2f} MB)")
    print("\n✅ 链路验证成功!可以用 `afplay` 或 QuickTime 播放该文件试听。")


if __name__ == "__main__":
    main()
