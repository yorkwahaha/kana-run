extends Node
## Sfx — 全程式化音訊：音效與自適應配樂。
##
## 專案不含任何音檔。啟動時用數學合成所有音色（AudioStreamWAV PCM），
## 配樂則由一個 16 分音符排程器即時驅動，強度會跟著玩家速度與連段攀升。

const MIX_RATE := 44100
const SFX_VOICES := 14
const MUSIC_VOICES := 10

const BUS_MASTER := "Master"
const BUS_MUSIC := "Music"
const BUS_SFX := "Sfx"

## 使用者可以自己丟音檔進來的位置（見 README）
const DIR_MUSIC := "res://audio/music/"
const DIR_SFX := "res://audio/sfx/"
const AUDIO_EXT := ["mp3", "ogg", "wav", "m4a"]

# ── 音樂理論 ────────────────────────────────────────────────────────────
## D 多利安調式音階，適合神社夜景的東方感又不會太陰暗
const SCALE := [0, 2, 3, 5, 7, 9, 10]   # 對 D 取相對半音
const ROOT_MIDI := 50                      # D3
const CHORDS := [                          # 每 4 小節的和聲 (相對音級)
	[0, 2, 4, 6],   # i7
	[5, 0, 2, 4],   # IV7
	[3, 5, 0, 2],   # vii°7 -> 借用
	[4, 6, 1, 3],   # v7 -> 借用
]

var _sfx_players: Array[AudioStreamPlayer] = []
var _music_players: Array[AudioStreamPlayer] = []
var _synth: Dictionary = {}
var _sfx_bank: Dictionary = {}
var _music_bus_idx := -1
var _sfx_bus_idx := -1

## 外部音檔：丟 mp3/ogg 進 res://audio/music 與 res://audio/sfx 即可覆蓋
var _ext_sfx: Dictionary = {}          ## 音效名 -> AudioStream
var _bgm_tracks: Array = []            ## 可用的背景音樂
var _bgm_player: AudioStreamPlayer
var _bgm_track_names: Array[String] = []
var _web_bgm_urls: Array[String] = []  ## Web 長音樂直接交給瀏覽器串流，不進 Godot Sample
var using_external_bgm := false
var _scan_timer := 0.0
var _music_sig := ""
var _sfx_sig := ""
var _silent_report := true
var _last_sfx_report := ""
var _bgm_mode := 1            ## 0 = 單曲循環, 1 = 全部輪播；新玩家預設輪播

# ── 配樂狀態 ────────────────────────────────────────────────────────────
var music_on := true
var intensity := 0.0          # 0..1，由 Main 依速度／連段設定
var _step := 0
var _step_timer := 0.0
var _step_len := 0.22
var _bar := 0
var _chord := 0
var _enabled_voices := 3
var _last_played_step := -1

# ── 風音效 ──────────────────────────────────────────────────────────────
var _wind: AudioStreamPlayer
var wind_gain_db := -60.0
var _weather := ""          ## 目前分區天氣（"" / rain / storm / combo）

## 佔住 manifest 的參照，並提供清單查詢。
##
## 為什麼需要：音訊與字型全都是用字串路徑在執行期動態載入的
## （DirAccess 掃描 + ResourceLoader.load），沒有任何場景或 .tscn 參照。
## 這在匯出後會壞兩次：
##   1. export_filter="all_resources" 只打包有相依關係的資源 → 整批音訊消失
##   2. DirAccess.get_files_at() 在 pck 裡讀不到目錄 → 掃描結果是空的
## 兩者的症狀都是「匯出成功、沒有任何錯誤訊息」，但遊戲會安靜地
## 退回內建程序化配樂。線上版就這樣少了 6.4MB 音訊。
##
## 改完 audio/ 或 assets/fonts/ 記得重跑 python tools/gen_manifest.py。
var _manifest: GDScript = preload("res://src/core/audio_manifest.gd")
var _manifest_keepalive: Array = _manifest.KEEPALIVE

## 掛在 window 上的音訊解鎖腳本。
## 用 String("\n").join(...)：GDScript 的 Array / PackedStringArray 都沒有
## join()，只有 String 有。const 也不接受方法呼叫，所以用 static var。
##
## 呼叫 Godot 自己的 _godot_audio_resume()，不要自己摸 AudioContext ——
## GodotAudio.ctx 是 index.js 的 module scope 區域變數，外部拿不到；
## 而 __godotAudioContexts 之類的名稱並不存在（那是臆測出來的，無效）。
static var WEB_AUDIO_UNLOCK_JS := String("\n").join(PackedStringArray([
	"(() => {",
	"  let tries = 0;",
	"  const tryResume = () => {",
	"    tries++;",
	"    // Godot 匯出的 index.js 把 _godot_audio_resume 掛在 Module 上，",
	"    // 它內部會檢查 GodotAudio.ctx.state 並呼叫 resume()。",
	"    const m = window.Module || {};",
	"    if (typeof m._godot_audio_resume === 'function') {",
	"      try { m._godot_audio_resume(); } catch (e) {}",
	"    }",
	"  };",
	"  for (const ev of ['pointerdown','touchstart','keydown','mousedown','click']) {",
	"    window.addEventListener(ev, tryResume, { passive: true, capture: true });",
	"  }",
	"  // Module 與 AudioContext 是在載入過程中陸續建立的，",
	"  // 所以前幾秒內多試幾次，涵蓋「使用者比引擎早點完」的情況。",
	"  for (let i = 0; i < 24; i++) {",
	"    setTimeout(tryResume, 250 + i * 250);",
	"  }",
	"})();",
	# 診斷：把 AudioContext 的狀態寫進畫面右下角，
	# 這樣「沒聲音」時可以一眼看出是 suspended 還是根本沒 ctx。
	# 沒有它就只能靠猜，而這個問題已經猜錯兩次了。
	# window.__kanaAudio 供 main.gd 的 --audiodebug 旗標讀取。
	"(() => {",
	"  const probe = () => {",
	"    const m = window.Module || {};",
	"    const ga = (typeof GodotAudio !== 'undefined') ? GodotAudio : null;",
	"    window.__kanaAudio = {",
	"      hasModule: !!m,",
	"      hasResume: typeof m._godot_audio_resume === 'function',",
	"      hasCtx: !!(ga && ga.ctx),",
	"      state: (ga && ga.ctx) ? ga.ctx.state : 'no-ctx',",
	"      rate: (ga && ga.ctx) ? ga.ctx.sampleRate : 0,",
	"      tries: window.__kanaAudio ? (window.__kanaAudio.tries + 1) : 1,",
	"    };",
	"  };",
	"  window.addEventListener('kanaprobe', probe);",
	"  setInterval(probe, 500);",
	"  probe();",
	"})();",
	]))


## ── 網頁版音訊解鎖 ──────────────────────────────────────────────────────
## 所有瀏覽器都禁止網頁在「沒有使用者互動」的情況下發聲。
## Web Audio API 的 AudioContext 初始是 suspended 狀態，
## 必須在使用者點過畫面之後呼叫 resume() 才會出聲。
##
## Godot 4 匯出的 index.js 裡有：
##     var GodotAudio = { ctx: AudioContext, ... }
##     function _godot_audio_resume() {
##       if (GodotAudio.ctx && GodotAudio.ctx.state !== 'running') GodotAudio.ctx.resume()
##     }
## ctx 是 module scope 的區域變數，無法從外部直接取得，
## 但 _godot_audio_resume() 掛在 window 上（Module 物件的成員），
## 所以從 JS 直接呼叫它是最乾淨的做法。
##
## 為什麼需要這個：Godot 自己的處理只涵蓋啟動畫面那一次點擊。
## 這個遊戲啟動後還要經過「標題 → 開始挑戰 → 設定」好幾層，
## iOS Safari 在這過程中不會自動恢復 AudioContext，
## 結果是「設定畫面顯示 BGM 2/4，但完全沒聲音」。
##
## 同時也要把 context 建好時的狀態記錄起來：
## 若使用者在我們掛事件之前就已經點過，後續事件也能再保險 resume 一次。
func _install_web_audio_unlock() -> void:
	if not OS.has_feature("web"):
		return
	var js := JavaScriptBridge
	if js == null:
		return
	js.eval(WEB_AUDIO_UNLOCK_JS, true)


## 除錯用：把瀏覽器的 AudioContext 狀態印到 console。
##
## 這個問題沒有任何錯誤訊息 —— 沒有聲音就是沒有聲音。
## 沒有這段就只能靠猜，而「沒聲音」的原因至少有四種
## （ctx 不存在 / suspended / ctx 被 resume 但 bus 靜音 / 音檔沒解碼），
## 猜錯的成本很高。
##
## 在瀏覽器主控台執行：  Sfx.audio_debug()
## 或啟動時加 --audiodebug，會在啟動後印一次完整報告。
func audio_debug() -> void:
	print("[audio] === 音訊診斷 ===")
	print("[audio] OS            : ", OS.get_name())
	print("[audio] feature web   : ", OS.has_feature("web"))
	print("[audio] mix rate      : ", AudioServer.get_mix_rate())
	print("[audio] bus count     : ", AudioServer.bus_count)
	# 網頁版會讀 .web 覆寫。0=Stream，1=Sample。印出 1 就是整局靜音的那條路。
	var playback := int(ProjectSettings.get_setting("audio/general/default_playback_type"))
	print("[audio] playback cfg  : ", playback, " (0=Stream 1=Sample)")

	print("[audio] --- bus 狀態 ---")
	for i in AudioServer.bus_count:
		var nm := AudioServer.get_bus_name(i)
		var vol := AudioServer.get_bus_volume_db(i)
		var mute := AudioServer.is_bus_mute(i)
		print("[audio]   [%d] %-8s vol=%7.1f dB mute=%s send=%s" % [
			i, nm, vol, str(mute), AudioServer.get_bus_send(i)])

	print("[audio] --- BGM ---")
	print("[audio] external bgm  : ", using_external_bgm)
	print("[audio] bgm tracks    : ", _bgm_tracks.size())
	print("[audio] ext sfx count : ", _ext_sfx.size())
	if OS.has_feature("web"):
		print("[audio]   HTML BGM : ", _web_bgm_eval("status()"))
	elif _bgm_player == null:
		print("[audio]   ★ _bgm_player 是 null")
	else:
		print("[audio]   playing     : ", _bgm_player.playing)
		print("[audio]   playback    : ", _bgm_player.playback_type)
		print("[audio]   volume_db   : %.1f" % _bgm_player.volume_db)
		print("[audio]   bus         : ", _bgm_player.bus)
		print("[audio]   stream      : ",
			_bgm_player.stream.get_class() if _bgm_player.stream != null else "null")
		if _bgm_player.stream != null:
			print("[audio]   length      : %.2f 秒" % _bgm_player.stream.get_length())
			var mp := _bgm_player.stream as AudioStreamMP3
			if mp != null:
				print("[audio]   loop        : ", mp.loop)
				print("[audio]   mix_rate    : ", mp.mix_rate)
				print("[audio]   stereo      : ", mp.stereo)

	print("[audio] --- 風聲 ---")
	if _wind == null:
		print("[audio]   ★ _wind 是 null")
	else:
		print("[audio]   playing     : ", _wind.playing)
		print("[audio]   volume_db   : %.1f" % _wind.volume_db)

	if OS.has_feature("web"):
		var js := JavaScriptBridge
		if js != null:
			print("[audio] --- 瀏覽器 ---")
			print("[audio]   ", js.eval(
				"JSON.stringify({isSecure: window.isSecureContext,"
				+ " hasAC: !!(window.AudioContext||window.webkitAudioContext)})", true))


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# _manifest_keepalive 的唯一作用是讓音訊進入資源依賴圖，
	# 這樣匯出時才會被打進 pck。詳見該變數的註解。
	assert(not _manifest_keepalive.is_empty(), "audio manifest 是空的，請跑 tools/gen_manifest.py")
	_setup_buses()
	_build_voices()
	_build_synth_bank()
	_build_sfx_bank()
	_start_wind()
	_install_web_audio_unlock()
	_bgm_mode = int(SaveGame.get_setting("bgm_mode", 1))
	_load_external()


# ── 外部音檔 ────────────────────────────────────────────────────────────
## res://audio/music/*.mp3  → 當作 BGM（隨機挑一首循環）
## res://audio/sfx/<name>.mp3 → 覆蓋同名的程序化音效
##   可覆蓋的 name：shift, shatter, miss, tap, back, tick
## 這樣想換音樂不必動任何程式碼。
func _load_external() -> void:
	_reload_sfx()
	_reload_music()

## Web BGM 使用獨立 HTMLMediaElement；短音效和題目語音仍使用 Godot Sample。
func _web_bgm_eval(expression: String) -> Variant:
	if not OS.has_feature("web"):
		return null
	return JavaScriptBridge.eval("window.__kanaBgm && window.__kanaBgm." + expression, true)


func _web_bgm_volume() -> float:
	return clampf(float(SaveGame.get_setting("master_volume", 0.9)), 0.0, 1.0) * clampf(
		float(SaveGame.get_setting("music_volume", 0.38)), 0.0, 1.0)


func _web_bgm_configure() -> void:
	_web_bgm_eval("setTracks(" + JSON.stringify(_web_bgm_urls) + ")")
	_web_bgm_eval("setMode(" + str(_bgm_mode) + ")")
	_web_bgm_eval("setVolume(" + str(_web_bgm_volume()) + ")")




## 掃描 music 資料夾。回傳檔案簽章（檔名串接）用來判斷有沒有變動。
##
## 為什麼不用 DirAccess.get_files_at()：
## 那個 API 在**匯出後的 pck 裡讀不到目錄內容**。桌機跑原始檔案時正常，
## 網頁版就是空的 —— 症狀是設定畫面寫「目前使用內建程序化配樂」，
## 而且沒有任何錯誤訊息。線上版就這樣靜靜地少了全部外部音訊。
##
## 改用 manifest 的清單（由 tools/gen_manifest.py 掃描實際檔案產生）。
## manifest 裡的每個項目都是 preload，資源一定在 pck 裡。
## 同時保留目錄掃描作為開發期的補充：使用者若在執行中丟檔進去，
## 桌機版仍能即時生效（遊戲每 2 秒會重掃一次）。
func _reload_music() -> void:
	_bgm_tracks.clear()
	_bgm_track_names.clear()
	_web_bgm_urls.clear()
	var sig := ""
	var seen := {}

	# 先走 manifest —— 這是唯一在匯出後可靠的來源
	for entry in _manifest.MUSIC:
		var path: String = entry["path"]
		if seen.has(path):
			continue
		seen[path] = true
		var stream := _try_load(path)
		if stream == null:
			continue
		_bgm_tracks.append(stream)
		_bgm_track_names.append(str(entry["name"]))
		_web_bgm_urls.append(path.trim_prefix("res://"))
		sig += path + "|"

	# 再補上目錄裡有、但 manifest 還沒收錄的（開發期丟檔的情況）
	if DirAccess.dir_exists_absolute(DIR_MUSIC):
		var names: Array[String] = []
		for f in DirAccess.get_files_at(DIR_MUSIC):
			if AUDIO_EXT.has(f.get_extension().to_lower()):
				names.append(f)
		names.sort()
		for f in names:
			var path := DIR_MUSIC + f
			if seen.has(path):
				continue
			seen[path] = true
			var stream := _try_load(path)
			if stream == null:
				continue
			_bgm_tracks.append(stream)
			_bgm_track_names.append(f.get_file().get_basename())
			_web_bgm_urls.append(path.trim_prefix("res://"))
			sig += path + "|"

	_music_sig = sig


	var had := using_external_bgm
	using_external_bgm = not _bgm_tracks.is_empty()
	if not using_external_bgm:
		if not _silent_report:
			print("[sfx] %s" % report())
			_silent_report = true
		return
	if not had:
		print("[sfx] %s" % report())
	_silent_report = false

	if OS.has_feature("web"):
		_web_bgm_configure()
		var idx := _web_bgm_eval("index")
		if not had or idx == null or int(idx) < 0:
			set_bgm_track(randi() % _bgm_tracks.size())
		return

	if _bgm_player == null:
		_bgm_player = _new_player(BUS_MUSIC)
		add_child(_bgm_player)
		_bgm_player.volume_db = linear_to_db(clampf(
			float(SaveGame.get_setting("music_volume", 0.38)), 0.0, 1.0))
		_bgm_player.finished.connect(_on_bgm_finished)
	if not had or _bgm_player.stream == null or _bgm_player.stream not in _bgm_tracks:
		set_bgm_track(randi() % _bgm_tracks.size())


## 跟 _reload_music 同一套。DirAccess.get_files_at() 在匯出後的 pck
## 讀不到目錄，所以先前網頁版 ext sfx count 一直是 0，6 個音效檔沒接上。
func _reload_sfx() -> void:
	_ext_sfx.clear()
	var sig := ""
	var seen := {}

	for entry in _manifest.SFX:
		var path: String = entry["path"]
		if seen.has(path):
			continue
		seen[path] = true
		var base := str(entry["name"])
		if not _sfx_bank.has(base):
			continue
		var stream := _try_load(path)
		if stream == null:
			continue
		_ext_sfx[base] = stream
		sig += path + "|"

	if DirAccess.dir_exists_absolute(DIR_SFX):
		var names: Array[String] = []
		for f in DirAccess.get_files_at(DIR_SFX):
			if AUDIO_EXT.has(f.get_extension().to_lower()):
				names.append(f)
		names.sort()
		for f in names:
			var path := DIR_SFX + f
			if seen.has(path):
				continue
			seen[path] = true
			sig += path + "|"
			var base := f.get_basename()
			if not _sfx_bank.has(base):
				continue
			var stream := _try_load(path)
			if stream != null:
				_ext_sfx[base] = stream
	_sfx_sig = sig
	if not _ext_sfx.is_empty() and sig != _last_sfx_report:
		_last_sfx_report = sig
		print("[sfx] 外部音效覆蓋：%s" % ", ".join(PackedStringArray(_ext_sfx.keys())))


## 每隔一陣子重掃一次：把 mp3 丟進資料夾就算已經在遊戲裡，
## 也會在幾秒內自己接上，不必重開。
func _poll_external(delta: float) -> void:
	_scan_timer -= delta
	if _scan_timer > 0.0:
		return
	_scan_timer = 2.0
	_dir_signature(DIR_MUSIC, "music")
	_dir_signature(DIR_SFX, "sfx")


func _dir_signature(dir: String, which: String) -> void:
	if not DirAccess.dir_exists_absolute(dir):
		return
	var names: Array[String] = []
	for f in DirAccess.get_files_at(dir):
		if AUDIO_EXT.has(f.get_extension().to_lower()):
			names.append(f)
	names.sort()
	var sig := ""
	for f in names:
		sig += f + "|"
	if which == "music" and sig != _music_sig:
		_reload_music()
	elif which == "sfx" and sig != _sfx_sig:
		_reload_sfx()


func _try_load(path: String) -> AudioStream:
	if not ResourceLoader.exists(path):
		return null
	var res := load(path)
	return res as AudioStream


## 切換背景音樂。回傳目前_track 名称；沒有外部音樂則回空字串。
func set_bgm_track(index: int) -> String:
	if not using_external_bgm or _bgm_tracks.is_empty():
		return ""
	var i := posmod(index, _bgm_tracks.size())
	if OS.has_feature("web"):
		_web_bgm_eval("playIndex(" + str(i) + ")")
		return _bgm_track_names[i]
	_bgm_player.stream = _bgm_tracks[i]
	_bgm_player.play()
	_apply_bgm_loop()
	return _bgm_track_names[i]


func next_bgm() -> String:
	if not using_external_bgm:
		return ""
	return set_bgm_track(_bgm_index() + 1)


func bgm_track_name() -> String:
	if OS.has_feature("web"):
		return _bgm_track_names[_bgm_index()] if not _bgm_track_names.is_empty() else ""
	if _bgm_player == null or _bgm_player.stream == null:
		return ""
	var i := _bgm_tracks.find(_bgm_player.stream)
	return _bgm_track_names[i] if i >= 0 else ""


func has_external_bgm() -> bool:
	return using_external_bgm


# ── 播放模式 ────────────────────────────────────────────────────────────
## Godot 匯入 mp3 預設 loop 關閉，所以「單曲循環」必須手動開 loop；
## 「全部輪播」則關閉 loop，靠 finished 訊號接下一首。
func set_bgm_mode(mode: int) -> void:
	_bgm_mode = clampi(mode, 0, 1)
	SaveGame.set_setting("bgm_mode", _bgm_mode)
	_apply_bgm_loop()
	if OS.has_feature("web"):
		return
	if _bgm_mode == 1 and _bgm_tracks.size() > 1 and not _bgm_player.playing:
		set_bgm_track(_bgm_index())


func bgm_mode() -> int:
	return _bgm_mode


func _apply_bgm_loop() -> void:
	if OS.has_feature("web"):
		_web_bgm_eval("setMode(" + str(_bgm_mode) + ")")
		return
	if not using_external_bgm or _bgm_player == null:
		return
	var want_loop := _bgm_mode == 0 or _bgm_tracks.size() <= 1
	for s in _bgm_tracks:
		# Godot 4.7：MP3 / OggVorbis 用 bool 的 loop；WAV 用 int 的 loop_mode
		if s is AudioStreamMP3:
			(s as AudioStreamMP3).loop = want_loop
		elif s is AudioStreamOggVorbis:
			(s as AudioStreamOggVorbis).loop = want_loop
		elif s is AudioStreamWAV:
			(s as AudioStreamWAV).loop_mode = 1 if want_loop else 0
	if want_loop and not _bgm_player.playing:
		_bgm_player.play()


func _bgm_index() -> int:
	if OS.has_feature("web"):
		var idx := _web_bgm_eval("index")
		return clampi(int(idx), 0, maxi(0, _bgm_tracks.size() - 1)) if idx != null else 0
	if _bgm_player == null or _bgm_player.stream == null:
		return 0
	return maxi(0, _bgm_tracks.find(_bgm_player.stream))


## 重新播放目前這首
func replay_bgm() -> void:
	if not using_external_bgm:
		return
	if OS.has_feature("web"):
		_web_bgm_eval("replay()")
		return
	if _bgm_player == null:
		return
	_bgm_player.stop()
	_bgm_player.play()


func _on_bgm_finished() -> void:
	if _bgm_mode == 1 and _bgm_tracks.size() > 1:
		set_bgm_track(_bgm_index() + 1)


func bgm_label() -> String:
	if not using_external_bgm:
		return "內建程序化配樂"
	return "%d / %d　%s" % [_bgm_index() + 1, _bgm_tracks.size(), bgm_track_name()]


func report() -> String:
	if using_external_bgm:
		return "外部 BGM：%s" % ", ".join(_bgm_track_names)
	return "內建程序化配樂（把 mp3 丟進 audio/music/ 即可替換）"


# ── 匯流排 ──────────────────────────────────────────────────────────────
func _setup_buses() -> void:
	# Web Sample + 動態 add_bus() 會引發 Godot #119026 無聲問題。
	# Web 只使用 Master，並改由各播放器控制 Music / Sfx 的音量。
	if not OS.has_feature("web"):
		_music_bus_idx = _ensure_bus(BUS_MUSIC)
		_sfx_bus_idx = _ensure_bus(BUS_SFX)
	_apply_volumes()


func _ensure_bus(name: String) -> int:
	var existing := AudioServer.get_bus_index(name)
	if existing >= 0:
		return existing
	AudioServer.add_bus()
	var idx := AudioServer.bus_count - 1
	AudioServer.set_bus_name(idx, name)
	AudioServer.set_bus_send(idx, BUS_MASTER)
	return idx


func _apply_volumes() -> void:
	var s: Dictionary = SaveGame.settings
	_set_bus_db(BUS_MASTER, linear_to_db(float(s.get("master_volume", 0.9))))
	if not OS.has_feature("web"):
		_set_bus_db(BUS_SFX, linear_to_db(float(s.get("sfx_volume", 0.9))))
		_set_bus_db(BUS_MUSIC, linear_to_db(float(s.get("music_volume", 0.38))))


## Web 不建立 Music/Sfx 子 bus，改在播放器套用設定；桌面版仍交給 bus 控制。
func channel_volume_db(bus: String) -> float:
	if not OS.has_feature("web"):
		return 0.0
	var key := "music_volume" if bus == BUS_MUSIC else "sfx_volume"
	var fallback := 0.38 if bus == BUS_MUSIC else 0.9
	return maxf(linear_to_db(clampf(float(SaveGame.get_setting(key, fallback)), 0.0, 1.0)), -80.0)


func _set_bus_db(bus: String, db: float) -> void:
	var i := AudioServer.get_bus_index(bus)
	if i >= 0:
		AudioServer.set_bus_mute(i, db <= -79.0)
		AudioServer.set_bus_volume_db(i, maxf(db, -80.0))


func refresh_volumes() -> void:
	_apply_volumes()
	if OS.has_feature("web"):
		_web_bgm_eval("setVolume(" + str(_web_bgm_volume()) + ")")
	if using_external_bgm and _bgm_player != null:
		_bgm_player.volume_db = linear_to_db(clampf(float(SaveGame.get_setting("music_volume", 0.38)), 0.0, 1.0))
	if OS.has_feature("web") and _wind != null:
		_wind.volume_db = wind_gain_db + channel_volume_db(BUS_SFX)


# ── 播放器池 ────────────────────────────────────────────────────────────
func _build_voices() -> void:
	for i in SFX_VOICES:
		var p := _new_player(BUS_SFX)
		add_child(p)
		_sfx_players.append(p)
	for i in MUSIC_VOICES:
		var p := _new_player(BUS_MUSIC)
		add_child(p)
		_music_players.append(p)


## 單執行緒 Web 的 Stream 音訊會跟著 3D 畫面掉幀而斷音。
## Web 使用 Sample + Master（不動態加 bus），桌面版保留 Stream。
func _new_player(bus: String) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.process_mode = Node.PROCESS_MODE_ALWAYS
	if OS.has_feature("web"):
		p.bus = BUS_MASTER
		p.playback_type = AudioServer.PLAYBACK_TYPE_SAMPLE
	else:
		p.bus = bus
		p.playback_type = AudioServer.PLAYBACK_TYPE_STREAM
	return p


func _free_voice(pool: Array[AudioStreamPlayer]) -> AudioStreamPlayer:
	for p in pool:
		if not p.playing:
			return p
	# 全忙就搶最老的一個
	return pool[randi() % pool.size()]


# ── 合成核心 ────────────────────────────────────────────────────────────
## 把浮點緩衝低通濾波 + 軟飽和之後轉成 16-bit PCM。
## 少了這一步，程序化合成的鋸齒波與高次諧波會非常刺耳。
func _render(duration: float, fn: Callable, lowpass_hz := 11000.0) -> AudioStreamWAV:
	var n := int(MIX_RATE * duration)
	var raw := PackedFloat32Array()
	raw.resize(n)
	for i in n:
		raw[i] = float(fn.call(float(i) / MIX_RATE, i))

	# 單極低通：把高頻（刺耳的來源）壓下來
	var dt := 1.0 / float(MIX_RATE)
	var rc := 1.0 / (TAU * maxf(lowpass_hz, 40.0))
	var a := dt / (rc + dt)
	var prev := 0.0
	for i in n:
		prev += a * (raw[i] - prev)
		raw[i] = prev

	# tanh 軟飽和：讓峰值圓潤，不會有數位截斷的爆音
	var buf := PackedByteArray()
	buf.resize(n * 2)
	for i in n:
		var v := tanh(raw[i] * 1.15) * 0.92
		v = clampf(v, -1.0, 1.0)
		var s := int(v * 32767.0)
		if s < 0:
			s += 65536
		buf.encode_s16(i * 2, s)
	var st := AudioStreamWAV.new()
	st.format = AudioStreamWAV.FORMAT_16_BITS
	st.mix_rate = MIX_RATE
	st.stereo = false
	st.data = buf
	return st


func _osc(phase: float, wave: String) -> float:
	var p := fposmod(phase, 1.0)
	match wave:
		"sine":
			return sin(p * TAU)
		"tri":
			return 4.0 * absf(p - 0.5) - 1.0
		"saw":
			return 2.0 * p - 1.0
		"square":
			return 1.0 if p < 0.5 else -1.0
		"pulse":
			return 1.0 if p < 0.25 else -1.0
		_:
			return sin(p * TAU)


## 帶指數衰減的包絡
static func env(t: float, attack: float, decay: float) -> float:
	if t < attack:
		return t / maxf(attack, 0.0001)
	return exp(-(t - attack) / maxf(decay, 0.0001))


func _build_synth_bank() -> void:
	# 柔和的木質撥弦（配樂主音）
	_synth["pluck"] = _render(0.55, func(t: float, _i: int):
		var e := env(t, 0.004, 0.16)
		var v := _osc(t, "sine") * 0.6 + _osc(t * 2.0, "tri") * 0.18
		return v * e, 5200.0)
	# 電子貝斯
	_synth["bass"] = _render(0.60, func(t: float, _i: int):
		var e := env(t, 0.006, 0.22)
		var v := _osc(t, "saw") * 0.35 + _osc(t, "sine") * 0.5
		return v * e * 0.9, 1800.0)
	# 木琴般的鐘（里程碑／提示）。刻意拿掉高次諧波 —— 那是刺耳的來源。
	_synth["bell"] = _render(1.6, func(t: float, _i: int):
		var e := env(t, 0.003, 0.30)
		var v := _osc(t * 440.0, "sine") * 0.5
		v += _osc(t * 440.0 * 2.0, "sine") * 0.16
		v += _osc(t * 440.0 * 3.01, "sine") * 0.05
		return v * e, 3400.0)
	# 寬廣 pad
	_synth["pad"] = _render(2.2, func(t: float, _i: int):
		var e := minf(t / 0.5, 1.0) * exp(-t / 1.4)
		var v := _osc(t * 220.0, "sine") * 0.4
		v += _osc(t * 220.0 * 1.5, "sine") * 0.18
		v += _osc(t * 220.0 * 2.0, "sine") * 0.12
		return v * e * 0.6, 2400.0)
	# 白噪音（碎石、打滑）
	_synth["noise"] = _render(0.7, func(t: float, _i: int):
		var e := env(t, 0.002, 0.13)
		return (randf() * 2.0 - 1.0) * e, 3000.0)
	# 上行琶音（完美答對）
	_synth["rise"] = _render(0.42, func(t: float, _i: int):
		var e := env(t, 0.002, 0.15)
		var f := 1.0 + t * 3.2
		return _osc(t * f * 520.0, "tri") * e * 0.7
	)
	# 下行掃頻（閃避）
	_synth["sweep"] = _render(0.36, func(t: float, _i: int):
		var e := env(t, 0.01, 0.11)
		var f := 1.0 - t * 1.8
		return (_osc(t * maxf(f, 0.05) * 700.0, "sine") * 0.6
			+ (randf() * 2.0 - 1.0) * 0.25) * e, 3200.0)


func _build_sfx_bank() -> void:
	# 換線：短促柔和的木頭敲擊
	_sfx_bank["shift"] = _render(0.13, func(t: float, _i: int):
		var e := env(t, 0.001, 0.035)
		return (_osc(t * 660.0, "tri") * 0.5 + _osc(t * 1320.0, "sine") * 0.2) * e, 4200.0)
	# 撞碎石碑：低頻衝擊 + 碎裂雜訊（雜訊壓低，不然會像撕紙）
	_sfx_bank["shatter"] = _render(0.55, func(t: float, _i: int):
		var body := _osc(t * (130.0 - t * 120.0), "sine") * env(t, 0.001, 0.11) * 0.85
		var crack := (randf() * 2.0 - 1.0) * env(t, 0.001, 0.07) * 0.28
		return body + crack, 3600.0)
	# 答錯：柔和的下行木質音（原本的不協和鋸齒太刺耳）
	_sfx_bank["miss"] = _render(0.42, func(t: float, _i: int):
		var f := 240.0 - t * 150.0
		var e := env(t, 0.006, 0.16)
		return (_osc(t * f, "tri") * 0.45 + _osc(t * f * 1.5, "sine") * 0.22) * e, 2000.0)
	# UI 點擊
	_sfx_bank["tap"] = _render(0.10, func(t: float, _i: int):
		var e := env(t, 0.001, 0.03)
		return _osc(t * 900.0, "sine") * e * 0.5, 4000.0)
	# UI 返回
	_sfx_bank["back"] = _render(0.14, func(t: float, _i: int):
		var e := env(t, 0.001, 0.05)
		return _osc(t * 420.0, "sine") * e * 0.45, 3200.0)
	# 倒數滴答
	_sfx_bank["tick"] = _render(0.08, func(t: float, _i: int):
		var e := env(t, 0.001, 0.02)
		return _osc(t * 1500.0, "sine") * e * 0.22, 3000.0)


# ── 播放 ────────────────────────────────────────────────────────────────
## 有外部音檔就用外部的，沒有才用程序化合成。
func play(name: String, pitch := 1.0, volume_db := 0.0) -> void:
	var stream: AudioStream = _ext_sfx.get(name, _sfx_bank.get(name))
	if stream == null:
		return
	var p := _free_voice(_sfx_players)
	p.stream = stream
	p.pitch_scale = clampf(pitch, 0.25, 4.0)
	p.volume_db = volume_db + channel_volume_db(BUS_SFX)
	p.play()


func play_wave(name: String, pitch := 1.0, volume_db := 0.0, bus := BUS_SFX) -> void:
	if not _synth.has(name):
		return
	var pool: Array[AudioStreamPlayer] = _music_players if bus == BUS_MUSIC else _sfx_players
	var p := _free_voice(pool)
	p.stream = _synth[name]
	p.pitch_scale = clampf(pitch, 0.1, 6.0)
	p.volume_db = volume_db + channel_volume_db(bus)
	p.play()


static func midi_to_ratio(semitones: float) -> float:
	return pow(2.0, semitones / 12.0)


func _chord_tone(degree: int, octave: int) -> float:
	var idx := posmod(degree, SCALE.size())
	var oct_shift := floori(float(degree) / float(SCALE.size()))
	var semis: float = float(SCALE[idx]) + 12.0 * float(oct_shift + octave)
	return midi_to_ratio(semis)


# ── UI / 玩法快捷音 ─────────────────────────────────────────────────────
func ui_tap() -> void: play("tap", randf_range(0.96, 1.05), -6.0)
func ui_back() -> void: play("back", 1.0, -5.0)
func lane_shift() -> void: play("shift", randf_range(0.95, 1.10), -8.0)
func tick() -> void: play("tick", 1.0, -12.0)


## 答對只用「石頭碎掉」這個實體音效回饋。
##
## 原本這裡有一條 bell 音階（每題升 2 半音、12 半音封頂），
## 結果封頂後整局都是同一個音，合成音聽久就膩。
## 現在拿掉音階，改用同一個碎裂音的音色差異（亮／暗、不加旋律），
## 玩家靠視覺與震動拿節奏，不靠耳朵爬音階。
func hit_perfect() -> void:
	play("shatter", 1.0, 1.5)
	play("shatter", 1.34, -7.0)   # 第二聲更亮的裂痕，取代音階作為獎勵


func hit_good() -> void:
	play("shatter", 1.0, -2.0)


## 換區提示：低沉木質撞擊 + 氣聲，不像旋律就不會膩
func zone_change(index: int) -> void:
	play("shift", 0.82, -2.0)
	play_wave("noise", 0.45, -6.0)
	# 每區一個固定的「圖章」音高：不是爬音階，是每區各自一個聲記號
	play_wave("bell", midi_to_ratio(float(index) * 5.0) * 0.5, -9.0)


## 衝刺關起步：往上推的風切聲
func sprint() -> void:
	play_wave("sweep", 1.25, -2.0)
	play("tick", 1.5, -6.0)


func miss() -> void:
	play("miss", 1.0, 1.0)
	play_wave("noise", 0.6, -4.0)


func dodge() -> void:
	play_wave("sweep", 1.0, -3.0)


func relic_pick() -> void:
	play_wave("bell", 1.0, -2.0)
	play_wave("bell", midi_to_ratio(7.0), -6.0)
	play_wave("bell", midi_to_ratio(12.0), -10.0)


func fanfare() -> void:
	play_wave("bell", 0.5, -1.0)
	play_wave("bell", midi_to_ratio(4.0) * 0.5, -4.0)
	play_wave("bell", midi_to_ratio(7.0) * 0.5, -7.0)
	play_wave("bell", midi_to_ratio(12.0) * 0.5, -3.0)


func countdown_tick(final := false) -> void:
	play("tick", 1.0 if not final else 1.5, -6.0)


func word_collect() -> void:
	play_wave("bell", 2.0, -10.0)


# ── 風聲 ────────────────────────────────────────────────────────────────
func _start_wind() -> void:
	_wind = _new_player(BUS_SFX)
	_wind.volume_db = -60.0 + channel_volume_db(BUS_SFX)
	var st := _render(2.0, func(t: float, _i: int):
		# 平滑的棕噪音感 + 緩慢起伏
		var base := (randf() * 2.0 - 1.0)
		var lfo := 0.6 + 0.4 * sin(t * 2.4)
		return base * lfo * 0.25
	)
	st.loop_mode = AudioStreamWAV.LOOP_FORWARD
	st.loop_begin = 0
	st.loop_end = int(MIX_RATE * 2.0)
	_wind.stream = st
	add_child(_wind)
	_wind.play()


## 由 Main 每幀呼叫：speed01 = 0..1
func set_wind(speed01: float, delta := 0.016) -> void:
	if _wind == null:
		return
	# 分區會改變音量與音色：草木是輕微的風聲、雨天才是雨聲、嵐最吵。
	# 原本不管哪一區都用同一組數值，所以整局都有一層持續的嘶嘶聲，
	# 進了雨區之後特別明顯，像有東西在反覆重播。
	var lo := -34.0
	var hi := -16.0
	var pitch := 0.85
	match _weather:
		"rain":
			lo = -24.0
			hi = -7.0
			pitch = 1.15
		"storm":
			lo = -22.0
			hi = -5.0
			pitch = 1.30
		"combo":
			lo = -38.0
			hi = -22.0
			pitch = 0.90
		_:
			pass
	var target := lerpf(lo, hi, clampf(speed01, 0.0, 1.0))
	wind_gain_db = lerpf(wind_gain_db, target, clampf(delta * 4.0, 0.0, 1.0))
	_wind.volume_db = wind_gain_db + channel_volume_db(BUS_SFX)
	_wind.pitch_scale = lerpf(pitch, pitch + 0.5, clampf(speed01, 0.0, 1.0))


## 分區天氣：決定風聲／雨聲的音量與音色（"" = 草木）
func set_weather(kind: String) -> void:
	_weather = kind


# ── 自適應配樂排程 ──────────────────────────────────────────────────────
## intensity 0..1 控制速度與層數
func set_intensity(v: float) -> void:
	intensity = clampf(v, 0.0, 1.0)
	_step_len = lerpf(0.255, 0.135, intensity)
	_enabled_voices = 2 + int(round(intensity * 3.0))


func music_enabled() -> bool:
	return music_on


func _process(delta: float) -> void:
	_poll_external(delta)
	if not music_on or using_external_bgm:
		return
	_step_timer += delta
	var guard := 0
	while _step_timer >= _step_len and guard < 8:
		_step_timer -= _step_len
		_emit_step(_step)
		_step += 1
		guard += 1
	if _step >= 16:
		_step = 0
		_bar += 1
		_chord = (_bar / 2) % CHORDS.size()


func _emit_step(step: int) -> void:
	if step == _last_played_step:
		return
	_last_played_step = step
	var chord: Array = CHORDS[_chord]
	var s := step % 16

	# 低音：每拍
	if s % 4 == 0:
		var root: int = int(chord[0])
		play_wave("bass", _chord_tone(root, 0) * 0.5, -14.0, BUS_MUSIC)

	# 琶音：8 分音符，強度越高越密
	var arp_every := 4 if _enabled_voices < 4 else 2
	if s % arp_every == 0:
		var idx := int(s / arp_every) % chord.size()
		var deg: int = int(chord[idx]) + (2 if idx == 0 else 0)
		play_wave("pluck", _chord_tone(deg, 2) * 0.5, -17.0, BUS_MUSIC)

	# 旋律點綴：高強度才出現
	if _enabled_voices >= 5 and s in [3, 7, 11, 15]:
		var deg2: int = int(chord[(s / 4) % chord.size()]) + 4
		play_wave("bell", _chord_tone(deg2, 3) * 0.5, -22.0, BUS_MUSIC)

	# Pad：每小節起頭
	if s == 0:
		for i in mini(2, chord.size()):
			play_wave("pad", _chord_tone(int(chord[i]), 1) * 0.5, -24.0, BUS_MUSIC)
