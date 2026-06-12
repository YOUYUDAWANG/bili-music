#!/usr/bin/env python3
"""验证 B 站搜索(WBI 签名) + 推荐数据源。

测三个接口:
  1. 搜索      /x/web-interface/wbi/search/type   (需 WBI 签名)
  2. 首页推荐  /x/web-interface/wbi/index/top/feed/rcmd  (类似 YM 首页推荐)
  3. 相关视频  /x/web-interface/archive/related     (类似 YM 电台/自动连播)

用法:
    python3 verify_search_rcmd.py "周杰伦 晴天"
    python3 verify_search_rcmd.py "周杰伦 晴天" --cookie "SESSDATA=xxx"

只用标准库。
"""

import hashlib
import json
import sys
import time
import urllib.parse
import urllib.request

HEADERS = {
    "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
                  "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36",
    "Referer": "https://www.bilibili.com",
}

# WBI mixinKey 重排表 (来自 bilibili-API-collect)
MIXIN_KEY_TAB = [
    46, 47, 18, 2, 53, 8, 23, 32, 15, 50, 10, 31, 58, 3, 45, 35, 27, 43, 5,
    49, 33, 9, 42, 19, 29, 28, 14, 39, 12, 38, 41, 13, 37, 48, 7, 16, 24,
    55, 40, 61, 26, 17, 0, 1, 60, 51, 30, 4, 22, 25, 54, 21, 56, 59, 6, 63,
    57, 62, 11, 36, 20, 34, 44, 52,
]

COOKIE = None


def http_get(url: str) -> dict:
    headers = dict(HEADERS)
    if COOKIE:
        headers["Cookie"] = COOKIE
    req = urllib.request.Request(url, headers=headers)
    with urllib.request.urlopen(req, timeout=15) as resp:
        return json.loads(resp.read().decode())


def get_mixin_key() -> str:
    nav = http_get("https://api.bilibili.com/x/web-interface/nav")
    wbi = nav["data"]["wbi_img"]
    img_key = wbi["img_url"].rsplit("/", 1)[1].split(".")[0]
    sub_key = wbi["sub_url"].rsplit("/", 1)[1].split(".")[0]
    raw = img_key + sub_key
    return "".join(raw[i] for i in MIXIN_KEY_TAB)[:32]


def wbi_sign(params: dict, mixin_key: str) -> str:
    params = dict(params, wts=int(time.time()))
    query = urllib.parse.urlencode(sorted(params.items()))
    w_rid = hashlib.md5((query + mixin_key).encode()).hexdigest()
    return query + "&w_rid=" + w_rid


def check(data: dict, name: str) -> dict:
    if data.get("code") != 0:
        raise RuntimeError(f"{name} 失败 code={data.get('code')}: {data.get('message')}")
    return data["data"]


def main() -> None:
    global COOKIE
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(1)
    keyword = sys.argv[1]
    if "--cookie" in sys.argv:
        COOKIE = sys.argv[sys.argv.index("--cookie") + 1]

    print("[0/3] 获取 WBI 签名密钥...")
    mixin_key = get_mixin_key()
    print(f"  mixin_key = {mixin_key}")

    # 1. 搜索
    print(f"\n[1/3] 搜索: {keyword}")
    q = wbi_sign({"search_type": "video", "keyword": keyword, "page": 1}, mixin_key)
    data = check(http_get(f"https://api.bilibili.com/x/web-interface/wbi/search/type?{q}"), "搜索")
    results = data.get("result") or []
    print(f"  共 {data.get('numResults')} 条,前 5 条:")
    for r in results[:5]:
        title = r["title"].replace('<em class="keyword">', "").replace("</em>", "")
        print(f"    - [{r['bvid']}] {title}  (UP: {r['author']}, 时长 {r['duration']})")
    first_bvid = results[0]["bvid"] if results else None

    # 2. 首页推荐流
    print("\n[2/3] 首页推荐流 (YM 首页推荐的数据源)")
    q = wbi_sign({"ps": 10, "fresh_idx": 1, "fresh_type": 4}, mixin_key)
    data = check(http_get(
        f"https://api.bilibili.com/x/web-interface/wbi/index/top/feed/rcmd?{q}"), "推荐流")
    for item in (data.get("item") or [])[:5]:
        print(f"    - [{item.get('bvid')}] {item.get('title')}  (UP: {item['owner']['name']})")

    # 3. 相关视频推荐
    if first_bvid:
        print(f"\n[3/3] 相关视频推荐 (基于 {first_bvid}, YM 电台/连播的数据源)")
        data = check(http_get(
            f"https://api.bilibili.com/x/web-interface/archive/related?bvid={first_bvid}"), "相关推荐")
        for item in (data or [])[:5]:
            print(f"    - [{item['bvid']}] {item['title']}  (UP: {item['owner']['name']})")

    print("\n✅ 全部验证完成")


if __name__ == "__main__":
    main()
