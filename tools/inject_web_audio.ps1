# 把 web/audio_unlock.html 注入 build/web/index.html
#
# 為什麼需要這支：
#   Godot 的 AudioContext 在 index.js 的 module scope 裡，既不在 window 上，
#   也無法從 GDScript 的 JavaScriptBridge 取得。唯一的機會是讓一段 script
#   在 index.js **之前** 執行，用 Proxy 包住 window.AudioContext 攔下引擎
#   建立的實例。
#
#   Godot 每次匯出都會重新產生 index.html，所以這支必須在匯出「之後」跑。
#   專案內的 export_presets.cfg 沒有對應選項（html/head_include 會被
#   Godot 放在 <head>，但 PWA 的 script 順序不受我們控制）。
#
# 失敗時不該讓整個匯出報錯 —— 沒有解鎖只是沒聲音，遊戲本身還能跑。
# 但要明確警告，不要靜靜地發布一個沒聲音的版本。

param(
    [string]$WebDir = "build\web",
    [string]$Source = "web\audio_unlock.html"
)

$ErrorActionPreference = "Stop"

$htmlPath = Join-Path $WebDir "index.html"
if (-not (Test-Path $htmlPath)) {
    Write-Error "找不到 $htmlPath（先跑 Godot 匯出）"
    exit 1
}
if (-not (Test-Path $Source)) {
    Write-Error "找不到 $Source"
    exit 1
}

$html = Get-Content $htmlPath -Raw -Encoding UTF8
$inject = Get-Content $Source -Raw -Encoding UTF8

# 已經注入過就不重複（避免重複的事件監聽器）
if ($html -match '__kanaAudioUnlock') {
    Write-Output "  already injected, skipping"
    exit 0
}

# 必須插在 index.js 之前，否則攔不到引擎建立的 AudioContext
$pattern = '(<script src="index\.js"></script>)'
if ($html -notmatch $pattern) {
    Write-Error "在 index.html 裡找不到 <script src=`"index.js`"></script>，無法定位插入點"
    exit 1
}

$html = $html -replace $pattern, ($inject + "`n`t" + '$1')
Set-Content -Path $htmlPath -Value $html -Encoding UTF8 -NoNewline

# 驗證插入位置正確
$lines = Get-Content $htmlPath
$injLine = ($lines | Select-String -Pattern '__kanaAudioUnlock' | Select-Object -First 1).LineNumber
$jsLine  = ($lines | Select-String -Pattern 'src="index\.js"' | Select-Object -First 1).LineNumber

if (-not $injLine -or -not $jsLine) {
    Write-Error "注入後無法確認位置（inject=$injLine index.js=$jsLine）"
    exit 1
}
if ($injLine -ge $jsLine) {
    Write-Error "注入位置錯誤：必須在 index.js（第 $jsLine 行）之前，實際在第 $injLine 行"
    exit 1
}

Write-Output "  injected at line $injLine (before index.js at line $jsLine)"
exit 0
