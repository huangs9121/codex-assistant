#!/usr/bin/env python3
"""发版后验证：模拟上一正式版客户端，走一遍 GitHub 自动更新链路。

用法（仓库根或任意目录）：
    python3 apps/codex-quota/Scripts/check_update_chain.py

校验 releases/latest 是否就是 version.env 中的版本，以及旧版客户端
发现、校验、下载该版本所需的全部条件。全部输出 PASS 才算通过。
"""
import hashlib
import json
import re
import subprocess
import sys
import urllib.request
from pathlib import Path
from urllib.parse import urlparse

ROOT = Path(__file__).resolve().parents[3]
env = (ROOT / "apps/codex-quota/Scripts/version.env").read_text()
current = re.search(r"APP_VERSION=([\d.]+)", env).group(1)
expected_tag = f"v{current}"

tags = subprocess.run(
    ["git", "tag", "--sort=-creatordate"],
    cwd=ROOT, capture_output=True, text=True, check=True,
).stdout.split()
prev_tag = next(
    (t for t in tags if t != expected_tag and re.fullmatch(r"v\d+\.\d+\.\d+", t)),
    "v0.0.0",
)
UA = f"Codex-Quota/{prev_tag[1:]}"  # 模拟上一正式版客户端

failures = 0
def check(name, cond, detail=""):
    global failures
    print(("PASS" if cond else "FAIL"), name, detail)
    if not cond:
        failures += 1

req = urllib.request.Request(
    "https://api.github.com/repos/huangs9121/codex-assistant/releases/latest",
    headers={"Accept": "application/vnd.github+json", "User-Agent": UA},
)
d = json.load(urllib.request.urlopen(req, timeout=15))

tag = d["tag_name"]
check("latest 即当前版本", tag == expected_tag, f"{tag} (期望 {expected_tag})")
check("非草稿非预发", not d["draft"] and not d["prerelease"])
u = urlparse(d["html_url"])
expected = f"/huangs9121/codex-assistant/releases/tag/{tag}"
check(
    "html_url 精确匹配",
    u.scheme == "https" and u.hostname == "github.com"
    and u.path == expected and not u.query and not u.fragment,
)
check(
    f"版本比较 {current} > {prev_tag[1:]}",
    tuple(map(int, current.split("."))) > tuple(map(int, prev_tag[1:].split("."))),
)

assets = [a for a in d["assets"] if a["name"] == "Codex.Quota-arm64.zip"]
check("匹配资产唯一", len(assets) == 1, f"共 {len(assets)} 个")
if assets:
    a = assets[0]
    check("contentType", a["content_type"] == "application/zip", a["content_type"])
    check("size 范围", 0 < a["size"] <= 100 * 1024 * 1024, f"{a['size']} bytes")
    digest = a.get("digest") or ""
    check(
        "sha256 digest 存在",
        digest.startswith("sha256:") and len(digest[7:]) == 64,
    )
    du = urlparse(a["browser_download_url"])
    exp_path = (
        f"/huangs9121/codex-assistant/releases/download/{tag}/Codex.Quota-arm64.zip"
    )
    check(
        "下载 URL 精确匹配",
        du.scheme == "https" and du.hostname == "github.com"
        and du.path == exp_path and not du.query and not du.fragment,
    )
    data = urllib.request.urlopen(
        urllib.request.Request(
            a["browser_download_url"],
            headers={"Accept": "application/octet-stream", "User-Agent": UA},
        ),
        timeout=60,
    ).read()
    check("下载 SHA-256 与 digest 一致", hashlib.sha256(data).hexdigest() == digest[7:])
    check("下载大小与声明一致", len(data) == a["size"], str(len(data)))

print("---")
print("RESULT:", "ALL-PASS" if failures == 0 else f"{failures} FAILURES")
sys.exit(0 if failures == 0 else 1)
