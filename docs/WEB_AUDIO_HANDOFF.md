# 網頁版完全靜默 — 除錯交接書

給接手除錯的 agent。請先讀完這份再動手，避免重走我走過的死路。

---

## 1. 現象

線上版 `https://yorkwahaha.github.io/kana-run/`（GitHub Pages，Godot 4.7.2 Web 匯出）：

- 遊戲畫面正常、可以玩
- **完全沒有任何聲音** — 連內建程序化音效都沒有
- 瀏覽器主控台**沒有** `The AudioContext was not allowed to start` 警告
- 設定畫面顯示 `外部 BGM：2 / 4 hit`，代表音檔有載入

已確認受影響：Chrome、Brave（桌機）、iPad Safari。
未受影響：Windows 原生版（`play.bat`）音訊完全正常。

---

## 2. 關鍵事實：Godot 端是正常的

用 `--audiodebug` 旗標印出的診斷（我加在 `src/core/sfx.gd` 的 `audio_debug()`）：

```
OS            : Web
mix rate      : 48000.0
bus count     : 3
  [0] Master   vol=  -0.9 dB  mute=false
  [1] Music    vol=  -8.4 dB  mute=false  send=Master
  [2] Sfx      vol=  -0.9 dB  mute=false  send=Master
external bgm  : true
bgm tracks    : 4
  playing     : true
  volume_db   : -8.4
  bus         : Music
  stream      : AudioStreamMP3
  length      : 136.22 秒
  loop        : true
--- 風聲 ---
  playing     : true
  volume_db   : -34.8
--- 瀏覽器 ---
  {"isSecure":true,"hasAC":true}
```

**這代表什麼**：Godot 認為自己在正常播放。bus 沒靜音、stream 有內容、player 在 playing、
`isSecureContext` 為 true。問題出在 **AudioContext 沒有真的 running**，
或者音訊送到瀏覽器之後被丟掉。

**還沒被解釋清楚的兩點**：
1. 沒有 `AudioContext was not allowed to start` 警告，但還是沒聲音。
   這個警告在 Chrome 上通常只在 context 建立時出現一次。如果 context 真的
   suspended，應該會看到。
2. `ext sfx count : 0` — `audio/sfx/` 的 6 個音效**沒有被載入**。
   只有 BGM 載入了。`_reload_sfx()` 走 `DirAccess.get_files_at()`，
   跟 `_reload_music()` 原本一樣的問題（我已把 music 改用 manifest，
   但 **sfx 還沒改**）。這可能是音效沒聲音的原因，也可能是無關的 bug。
   **這是我認為下一個最值得查的線索。**

---

## 3. 我試過但行不通的方法

### 3.1 `window.__godotAudioContexts` — 不存在

在 `Sfx._install_web_audio_unlock()` 裡假設引擎把 AudioContext 陣列放在
`window.__godotAudioContexts`，寫了事件監聽器去 resume 它們。

**為什麼不行**：那個名稱是我憑空想像的。`index.js` 裡沒有任何東西會建立它。
Console 顯示我的腳本**有執行**（`tries` 從 43 增加到 46，代表事件監聽器確實生效），
但 resume 的目標不存在，所以是靜默的 no-op。

### 3.2 `Module._godot_audio_resume()` — 拿不到

`index.js` 裡確實有這支函式：

```js
function _godot_audio_resume(){
  if(GodotAudio.ctx && GodotAudio.ctx.state!=="running"){GodotAudio.ctx.resume()}
}
```

**為什麼不行**：它不是 `Module` 的成員。它是 Emscripten 的 **wasm import 函式**，
掛在 `wasmImports` 物件裡（壓縮後是 `wasmImports.qa = _godot_audio_resume`），
**只給 wasm 內部呼叫**，沒有掛到 `window` 也沒有掛到 `Module`。

我驗證過：
```
[regex]::Matches($js, 'Module\["(_godot_audio[^"]*)"\]')   → 0 筆
[regex]::Matches($js, 'Module\.(_godot_audio\w+)')        → 0 筆
$js -match 'qa:_godot_audio_resume'                        → True（只在 wasmImports）
```

### 3.3 `GodotAudio.ctx` 直接存取 — module scope 看不到

`var GodotAudio = { ... ctx: AudioContext ... }` 宣告在 `index.js` 頂層，
但 `index.js` 是 Emscripten 輸出，整個檔案包在 IIFE / module 裡。

**為什麼不行**：從 `Runtime.evaluate`（瀏覽器主控台）和
`JavaScriptBridge.eval()`（GDScript）都是**全域作用域**，看不到 module scope。
我寫的探針一直回報 `hasGodotAudio: false`，那個 `false` 是**探針的盲區**，
不是真的沒有 GodotAudio 物件。這個誤導了我一段時間。

### 3.4 用 prototype getter 包住 `AudioContext` — 引擎直接起不來

```js
Object.defineProperty(TrackedAudioContext.prototype, k, {
  get() { return ctx[k]; },   // ← ctx 不在作用域內
  ...
});
```

**為什麼不行**：getter 定義在 `TrackedAudioContext.prototype` 上，
但 `ctx` 是建構式 `TrackedAudioContext()` 的**區域變數**，
在 getter 的作用域裡不存在。瀏覽器拋：

```
ReferenceError: ctx is not defined
    at AudioContext.get (index.html:152:19)
    at ctx.onstatechange (index.js:1:148037)
    at Object.init (index.js:1:148164)
    at _godot_audio_init (index.js:1:152605)
```

**注意**：這讓**整個引擎啟動失敗**（音訊初始化在主迴圈之前），
畫面會全黑。若下一位 agent 看到黑畫面，先檢查是不是又改壞了這段。

**改成 Proxy 後解決**：`Proxy` 的 `construct` / `get` 陷阱跟 `ctx` 在同一個閉包裡，
作用域正確。實測 `resumeAll n=1 tracked=1`，警告消失。

### 3.5 把 BGM 從 Ogg Vorbis 改回 MP3 — 解決的是另一個問題

原本我把 BGM 從 MP3 壓成 Ogg Vorbis（12.36 → 5.77 MB）。
**這個改動是必要的**（iOS Safari 要 18.4 才支援 Ogg），
但**它沒有解決你回報的靜默**。你是在 Chrome/Brave 上也沒聲音，
而 Chrome 一直支援 Ogg。

改回 MP3 112k/44.1kHz 之後：1.82 MB，比 Ogg 的 1.86 MB 還小，
而且相容性完全不一樣。這個改動請保留。

### 3.6 `default_playback_type = "Stream"` — 可能有用但無法證實

Godot 4.3+ 在 web 預設 Sample 播放模式。官方文件說可以用
`Audio > General > Default Playback Type` 改成 Stream 取得完整音訊功能。
我改了，但**沒有證據顯示這解決了問題**（headless 測不出聲音）。

保留這個設定，因為它符合官方建議，但**不要假設它是答案**。

### 3.7 headless Chrome 驗證音訊 — 原理上做不到

我寫了 Chrome DevTools Protocol 腳本（`I:\WinTemp\opencode\*.mjs`）想驗證解鎖。

**為什麼不行**：
- CDP 的 `Input.dispatchMouseEvent` 是**合成事件，不算使用者手勢**。
  Web Audio 的 autoplay 閘門只認真實手勢。
- `GodotAudio` 在 module scope，`Runtime.evaluate` 看不到。
- headless 沒有音訊輸出裝置，無法確認「真的有聲音」。

可以驗證的是「腳本有沒有執行、有沒有呼叫 resume」，
**不能**驗證「使用���聽得到聲音」。這件事只能由真實瀏覽器確認。

### 3.8 命令列除錯旗標在 web 版無效

`OS.get_cmdline_user_args()` 在 web 匯出的 wasm 裡**沒有實作**，回傳空陣列。

**影響**：我先前說「在 web 版用 `--flung` 測試」是無效的，那些測試從來沒生效過。
我後來改成網址 query string：`index.html?debug=audiodebug`（實作見
`Main._web_debug_flags()`）。

---

## 4. 目前線上的狀態

已部署的部分：

- `web/audio_unlock.html` — 音訊解鎖 script，透過 `tools/inject_web_audio.ps1`
  注入到 `index.html` 的 `<script src="index.js">` **之前**。
  CI 會驗證注入成功，沒注入就讓建置失敗。
- `src/core/audio_manifest.gd` — 解決了「音訊沒被打包 / 執行期掃不到目錄」。
  這是**真實修好的問題**，請保留。詳細原因見該檔案的開頭註解。
- `project.godot` 的 `default_playback_type="Stream"`
- BGM 已改回 MP3 112k/44.1kHz

**仍然靜默。** 注入的解鎖 script 在我的測試裡確實執行了
（`resumeAll n=1 tracked=1`，AudioContext 警告消失），
但**沒有讓聲音出來**。

---

## 5. 建議的下一步

按優先順序：

### 5.1 先查 `ext sfx count: 0`（我認為最可能的原因）

`audio/sfx/` 的 6 個音效沒被載入。`_reload_music()` 我已經改用
`audio_manifest.gd` 的清單，但 **`_reload_sfx()` 還在用
`DirAccess.get_files_at()`**（`src/core/sfx.gd`）。

`DirAccess.get_files_at()` 在匯出後的 pck 裡讀不到目錄內容 ——
這是 BGM 遇到的同一個問題，我當時只修了 music 沒修 sfx。

**做法**：把 `_reload_sfx()` 改成讀 `manifest.SFX` 清單，跟 `_reload_music()` 同一套寫法。
`Curriculum` 的語音包（`LISTENING_DIR`，`audio/kana/`）可能也有同樣問題，
`curriculum.gd:32` 和 `curriculum.gd:277` 都還是 `DirAccess.dir_exists_absolute()`。

### 5.2 在真實瀏覽器確認 AudioContext 狀態

headless 測不出來，必須請使用者在 F12 主控台執行：

```js
// 這會列出所有瀏覽器層級的 AudioContext
// 看不到 GodotAudio（module scope），但可以看到有幾個 context 存活
performance.getEntriesByType('resource').filter(r => r.name.includes('wasm'));
```

或直接在主控台看我的診斷輸出（網址加 `?debug=audiodebug`，
會在啟動後每 2 秒印一次，共 6 次）。

**關鍵要確認的**：點過畫面之後，`GodotAudio.ctx.state` 是不是 `running`。
這在瀏覽器外部量不到，但可以在 `audio_debug()` 裡加一段
`js.eval` 去猜（我知道 module scope 看不到，若你有其他方法取得更好）。

### 5.3 考慮改用 HTML5 Audio 播放

如果 AudioContext 這條路走不通，Godot 官方有另一個選項：
把 `AudioStreamPlayer` 的 `playback_type` 設成 `Stream`（已做），
或檢查 `audio/driver/enable_input` 之類的 driver 設定。

`project.godot` 目前有 `driver/enable_input=false`，這是預設值，
但值得確認有沒有其他 driver 選項會影響 web。

### 5.4 排除 PWA / Service Worker 快取

`export_presets.cfg` 開了 `progressive_web_app/enabled=true`，
Service Worker 會快取舊的 pck。使用者可能一直在看舊版本。

**請先請使用者清除網站資料**再測試，或暫時關掉 PWA 排除這個變因：

```ini
progressive_web_app/enabled=false
```

這我沒有做，因為 PWA 是刻意的功能，但如果它造成難以測試，
暫時關掉是合理的。

---

## 6. 相關檔案

| 檔案 | 角色 |
|---|---|
| `src/core/sfx.gd` | 音訊核心。`_reload_music()` 已改用 manifest，`_reload_sfx()` **還沒** |
| `src/core/audio_manifest.gd` | 資源清單（自動產生，勿手動編輯）。解決打包 + 執行期載入 |
| `tools/gen_manifest.py` | 產生上面的 manifest。改完 `audio/` 要重跑 |
| `web/audio_unlock.html` | 音訊解鎖 script，注入到 index.js 之前 |
| `tools/inject_web_audio.ps1` | 把上面那支注入到匯出後的 index.html |
| `project.godot` | `[audio]` 區段，`default_playback_type="Stream"` |
| `export_presets.cfg` | 匯出設定。`thread_support=false`、`vram_compression/mobile=false` |
| `.github/workflows/deploy-web.yml` | 自動部署，會驗證音訊打包與解鎖注入 |
| `README.md` | 有一節記錄「網頁版沒聲音時的排查順序」 |

## 7. 可用的除錯工具

```bash
# 完整音訊診斷（桌機）
godot --headless --path . --script ...  # 不行，autoload 沒載入
godot --path . -- --audiodebug          # 用這個

# 網頁版診斷：網址加 ?debug=audiodebug

# 檢查 pck 裡有沒有音訊
grep -c '\.mp3str' build/web/index.pck

# 匯出 + 注入解鎖 script
export-web.bat

# 檢查注入有沒有成功
Select-String -Path build/web/index.html -Pattern '__kanaAudioUnlock'
```

診斷碼 `window.__kanaAudioUnlock` 是可呼叫的函式，在瀏覽器主控台執行
`window.__kanaAudioUnlock()` 可以強制再 resume 一次。

---

## 8. 我犯的錯，記下來避免重蹈

1. **猜 API 名稱** — `__godotAudioContexts` 是憑空想像的。
   應該先讀 `index.js` 確認名稱存在。
2. **看到錯誤訊息就下結論** — `hasGodotAudio: false` 是我的探針在 module
   scope 外面看不到，不是真的沒有。我把它當成「引擎沒建立 context」，
   浪費了一整輪。
3. **混淆兩個獨立問題** — Ogg 格式（iOS Safari 不支援）和 AudioContext
   解鎖是兩件事。我一度以為改回 MP3 就會有聲音。
4. **在無法驗證的環境下宣稱驗證** — headless 測不出音訊，
   我卻說「修正有效」。實際上只是腳本有執行而已。
