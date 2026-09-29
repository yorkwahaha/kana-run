"""產生 audio_manifest.gd。

為什麼需要這個檔案
------------------
專案裡的音訊與字型全都是**執行期用字串路徑動態載入**的
（見 `src/core/sfx.gd` 的目錄掃描、`FontKit` 的 `PATH_UI` 之類的字串常數）。

Godot 的 `export_filter="all_resources"` 只打包**被場景或 .tscn 參照到**
的資源。用字串組出來的路徑對匯出器而言就是「沒人用」，
所以音訊會整個從 pck 裡消失。

症狀非常有迷惑性：匯出回報成功、遊戲照跑、但設定畫面寫
「目前使用內建程序化配樂」，而且沒有任何錯誤訊息。
線上版就這樣少了 6.4MB 音訊 —— 只有比對 pck 大小或印出 BGM 清單
才看得出來。

第二個問題在執行期：`DirAccess.get_files_at()` 在匯出後的 pck 裡
讀不到目錄內容。桌機跑原始檔案正常，網頁版就是空的。

解法是讓這些檔案進入資源依賴圖，同時提供一份明確的清單。

格式選擇：全部用 MP3，不要用 Ogg
--------------------------------
Ogg Vorbis 壓縮率較好，但 **iOS Safari 要到 18.4 才支援**
（更早的版本是 partial 或完全不支援）。iPad 使用者會遇到
「音效有聲音、BGM 完全靜默」—— 因為 SFX 和語音包是 MP3，
只有 BGM 被換成 Ogg。

實測過的取捨（同一首 2:16 的曲子）：
    MP3 192k 48kHz（原始）        3.37 MB
    Ogg Vorbis q5 44.1kHz         1.86 MB   ← Safari 播不了
    MP3 VBR q4 44.1kHz            2.56 MB
    MP3 CBR 112k 44.1kHz         1.82 MB   ← 選這個
CBR 112k 比 Ogg 還小一點，而且所有瀏覽器都支援。
"""

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "src" / "core" / "audio_manifest.gd"

# 與 sfx.gd 的 AUDIO_EXT 保持一致
AUDIO_EXT = {".ogg", ".mp3", ".wav", ".m4a"}

HEADER = '''class_name AudioManifest
extends RefCounted
## 音訊與字型的資源清單（由 tools/gen_manifest.py 產生，請勿手動編輯）。
##
## 這個檔案存在的理由是**兩件在匯出後會壞掉的事**：
##
## 1. 打包階段：音訊與字型全都是用字串路徑在執行期動態載入的，
##    沒有任何場景或 .tscn 參照。`export_filter="all_resources"`
##    只打包有相依關係的資源，於是整批音訊從 pck 裡消失。
##
## 2. 執行階段：`DirAccess.get_files_at("res://audio/music/")`
##    在匯出後的 pck 裡讀不到目錄內容。桌機跑原始檔案正常，
##    網頁版就是空的。
##
## 兩者的症狀都是「匯出成功、沒有任何錯誤訊息」，但遊戲會安靜地
## 退回內建程序化配樂，設定畫面寫「目前使用內建程序化配樂」。
## 線上版曾因此整整少了 6.4MB 音訊，只有比對 pck 大小或
## 印出 BGM 清單才看得出來。
##
## 這個檔案同時解決兩者：每個項目都是 preload（建立相依關係），
## 並提供分組清單供執行期查詢。
##
## 改完 audio/ 或 assets/fonts/ 記得重跑：
##     python tools/gen_manifest.py
##
## 為什麼自動產生而不是手寫：README 說使用者可以自己丟音檔進
## audio/music/ 與 audio/sfx/。手寫清單在這種設計下必然腐化 ——
## 使用者加了新檔卻忘了更新，新檔在網頁版就會靜靜地不見。

'''


def keepalive_block(audio: list[tuple[str, str]], fonts: list[tuple[str, str]]) -> str:
    """產生 KEEPALIVE 陣列，把每個 preload 都收進去。"""
    names = [f"A_{ident(n).upper()}" for n, _ in audio]
    names += [f"F_{ident(n).upper()}" for n, _ in fonts]
    lines = ["const KEEPALIVE: Array = [\n"]
    for n in names:
        lines.append(f"\t{n},\n")
    lines.append("]\n")
    return "".join(lines)


def collect() -> dict[str, list[tuple[str, str]]]:
    """回傳各資料夾的 (顯示名稱, res:// 路徑) 清單。"""
    out: dict[str, list[tuple[str, str]]] = {"music": [], "sfx": [], "kana": [], "words": []}
    for sub in out:
        d = ROOT / "audio" / sub
        if not d.is_dir():
            continue
        for f in sorted(d.iterdir()):
            if f.suffix.lower() in AUDIO_EXT:
                out[sub].append((f.stem, f"res://audio/{sub}/{f.name}"))

    fonts: list[tuple[str, str]] = []
    fd = ROOT / "assets" / "fonts"
    if fd.is_dir():
        for f in sorted(fd.iterdir()):
            if f.suffix.lower() == ".ttf":
                fonts.append((f.stem, f"res://assets/fonts/{f.name}"))
    out["fonts"] = fonts
    return out


def word_ident(name: str) -> str:
    """平假名檔名沒有合法的識別字，改用碼位，避免全部變成底線後撞名。"""
    parts: list[str] = []
    for ch in name:
        if ch.isascii() and (ch.isalnum() or ch == "_"):
            parts.append(ch)
        else:
            parts.append(f"u{ord(ch):04X}")
    body = "".join(parts)
    if not body or body[0].isdigit():
        body = "n" + body
    return body


def const_name(sub: str, name: str) -> str:
    if sub == "words":
        return "A_WORD_" + word_ident(name).upper()
    return "A_" + ident(sub + "_" + name).upper()


def ident(name: str) -> str:
    """把檔名轉成合法的 GDScript 識別字元。

    語音包有 'tsu'、'chi' 這種，用底線隔開避免撞到關鍵字。
    """
    return re.sub(r"[^0-9a-zA-Z_]", "_", name)


def keepalive_block(groups: dict[str, list[tuple[str, str]]]) -> str:
    """產生 KEEPALIVE 陣列，把每個 preload 都收進去。"""
    names: list[str] = []
    for sub in ("music", "sfx", "kana", "words"):
        names += [const_name(sub, n) for n, _ in groups[sub]]
    names += [f"F_{ident(n).upper()}" for n, _ in groups["fonts"]]
    lines = ["const KEEPALIVE: Array = [\n"]
    for n in names:
        lines.append(f"\t{n},\n")
    lines.append("]\n")
    return "".join(lines)


def list_block(groups: dict[str, list[tuple[str, str]]], sub: str) -> str:
    """產生一個 [{name, path}, ...] 的常數陣列。"""
    lines = [f"const {sub.upper()}: Array = [\n"]
    for name, path in groups[sub]:
        lines.append(f'\t{{"name": "{name}", "path": "{path}"}},\n')
    lines.append("]\n")
    return "".join(lines)


def main() -> int:
    groups = collect()
    parts = [HEADER]

    parts.append("## ── 音訊 ──\n")
    for sub in ("music", "sfx", "kana", "words"):
        for name, path in groups[sub]:
            parts.append(f'const {const_name(sub, name)} := preload("{path}")\n')
    parts.append("\n## ── 字型 ──\n")
    for name, path in groups["fonts"]:
        parts.append(f'const F_{ident(name).upper()} := preload("{path}")\n')

    parts.append(
        "\n## ── 分組清單 ──\n"
        "## Sfx 與 Curriculum 讀這三個清單，取代 DirAccess 目錄掃描。\n"
    )
    for sub in ("music", "sfx", "kana", "words"):
        parts.append("\n" + list_block(groups, sub))

    parts.append("\n## 必須被 sfx.gd 讀取，否則資源分析器會丟棄以上所有相依關係。\n")
    parts.append(keepalive_block(groups))

    OUT.write_text("".join(parts), encoding="utf-8")
    total = sum(len(groups[s]) for s in ("music", "sfx", "kana", "words"))
    print(f"[manifest] 寫入 {OUT.relative_to(ROOT)}")
    print(f"[manifest] music={len(groups['music'])} sfx={len(groups['sfx'])} "
          f"kana={len(groups['kana'])} words={len(groups['words'])} "
          f"fonts={len(groups['fonts'])} (音訊共 {total})")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
