extends Node3D
## Main — 遊戲流程總調。
##
## 狀態機：TITLE → PLAY ⇄ PAUSED → RELIC → RESULTS
## 波次生命週期：GAP（空檔）→ 一顆石碑推進 → 判定 → GAP …
## 每幀推進都吃 delta，60Hz 與 120Hz 手機跑起來完全一致。

const LANE_X := [-2.7, 0.0, 2.7]
const LANE_COUNT := 3

const SPAWN_Z := -50.0
const LEGIBLE_Z := -24.0

const SPEED_MIN := 13.0
const SPEED_MAX := 42.0

const STAMINA_MAX := 100.0
const STAMINA_HEAL := 8.0
const STAMINA_WRONG := 12.0
const STAMINA_DODGE := 9.0

const RELIC_EVERY := 10
const DODGE_WINDOW := 0.52
const OBSTACLE_EVERY := 5       ## 每幾題插入一個橫桿障礙

# ── 極限（OVERDRIVE）─────────────────────────────────────────────────────
## 熱度灌滿就爆開約七秒：分數 ×3、速度墊高、體力掉更快，時間到自己結束。
## 答錯會把還沒爆開的熱度清掉；已經在跑的那一波會自己走完。
const OVERDRIVE_NEED := 8.0       ## 累積這麼多「熱度」就爆開一波極限
const OVERDRIVE_TIME := 7.0       ## 極限持續秒數，期間體力掉得更快
const OVERDRIVE_MULT := 3.0
## 極限下石碑的閱讀時間倍率。越小 = 必須更早認出來，壓力越大。
const OVERDRIVE_LEGIBLE := 0.55
## 極限下的體力消耗倍率。
const OVERDRIVE_DRAIN := 1.9
## 極限時速度加成，讓畫面本身也跟著興奮起來。
const OVERDRIVE_BOOST := 1.18

# ── 分區 ────────────────────────────────────────────────────────────────
## 為什麼要分區：原本一局 46 題是「一直加速的斜坡」，除了難度上升
## 之外沒有任何結構，玩起來像在讀一份清單。切成四區之後每一區有名字、
## 有自己的天色與天氣、還有各自的玩法 twist，玩家會為了「再撐一區」繼續跑。
const ZONE_LEN := 12
const SPRINT_TIME := 3.2       ## 衝刺關持續秒數
const SPRINT_BOOST := 1.22     ## 衝刺時的速度倍率
const SPRINT_MULT := 2.0       ## 衝刺時的得分倍率
const ZONES := [
	{
		"title": "第一區", "place": "草木", "twist": "none",
		"fog": Color(0.20, 0.16, 0.32), "density": 0.0042,
		"weather": Vector3(0.6, -0.5, 0), "petal": Color(1.0, 0.80, 0.90),
		"note": "先熟悉節奏",
	},
	{
		"title": "第二區", "place": "雨", "twist": "rain",
		"fog": Color(0.17, 0.22, 0.36), "density": 0.0092,
		"weather": Vector3(1.4, -9.0, 0), "petal": Color(0.72, 0.86, 1.0),
		"note": "雨勢加大，路面更滑",
	},
	{
		"title": "第三區", "place": "神社", "twist": "combo",
		"fog": Color(0.26, 0.17, 0.34), "density": 0.0058,
		"weather": Vector3(0.2, -1.2, 0), "petal": Color(1.0, 0.72, 0.52),
		"note": "連段倍率成長加倍",
	},
	{
		"title": "第四區", "place": "嵐", "twist": "storm",
		"fog": Color(0.34, 0.14, 0.20), "density": 0.0135,
		"weather": Vector3(3.2, -7.0, 0), "petal": Color(1.0, 0.55, 0.42),
		"note": "最強風速，撐到終點",
	},
]
const TITLE_SPEED := 7.0

enum State { TITLE, PLAY, PAUSED, RELIC, RESULTS, COLLAPSE }

## 開發用：從命令列參數開啟自動陪玩與截圖，方便無顯示器時做回歸測試。
##   godot --path . -- --autoplay            機器人自動答題跑完整局
##   godot --path . -- --shot 90 out.png     第 90 幀截圖
const ARG_AUTOPLAY := "--autoplay"
const ARG_SHOT := "--shot"
const ARG_TURBO := "--turbo"

var state := State.TITLE
var unit_kinds: Array = []

# ── 場景 ──
var _track: Node3D
var _runner: Node3D
var _cam: Camera3D
var _hero_light: OmniLight3D
var _stones: Array[Node3D] = []
var _gem: Node3D
var _barrier: Node3D
var _gem_core: MeshInstance3D
var _gem_label: Label3D
var _post_mat: ShaderMaterial
var _hud: Control
var _ui: Control

# ── 流程 ──
var _question: Dictionary = {}
var _wave_active := false
var _wave_z := 0.0
var _obstacle_timer := 0
var _obstacle_wave := false
var _zone := 0
var _fog_target := Color(0, 0, 0)
var _fog_density_target := 0.0048
var _sprint := 0.0            ## 衝刺關剩餘秒數
var _last_combo_milestone := 0
var _gap := 0.0
var _duck_timer := 0.0
var _legible_time := 0.0
var _lane := 1
var _gem_lane := 0
var _gem_z := 0.0
var _gem_t := 0.0
var _gem_word: Array = []
var _gem_active := false
var _fades: Array = []

# ── 數值 ──
var _stamina := STAMINA_MAX
var _stamina_cap := STAMINA_MAX
var _score := 0
var _chain := 0
var _best_chain := 0
var _overdrive := false
var _overdrive_t := 0.0
var _od_charge := 0.0
var _resolved := 0
var _speed := SPEED_MIN
var _shake_user := 1.0
var _reduce_motion := 0.0
var _time_scale_target := 1.0
var _hitstop_until_ms := 0    ## 打擊停滯結束時限（真實時鐘）
var _damage_flash := 0.0
var _good_flash := 0.0
var _relics: Dictionary = {}
var _next_relic_at := RELIC_EVERY
var _title_orbit := 0.0

var _autoplay := false
var _autoplay_sabotage := true
var _always_miss := false
var _hold_miss := false
var _watch := false
var _hold_relic := false
var _hold_end := false
var _forced_type := -1
var _voice_player: AudioStreamPlayer
var _test_page := ""
var _shot_frame := -1
var _shot_path := ""
var _turbo := 1.0
var _frames := 0


func _ready() -> void:
	# Main 本身要 ALWAYS：暫停與遺物畫面會 pause 整棵樹，
	# 但流程轉換（暫停選單、機器人自動選遺物）仍需要它醒著。
	# 3D 節點則個別設為 PAUSABLE，暫停時場景才會真的凍結。
	process_mode = Node.PROCESS_MODE_ALWAYS
	_parse_test_args()
	_build_world()
	_build_ui()
	_connect_ui()
	_apply_settings()
	# 暖機必須在 _start_run 之前跑完。
	# 放在標題畫面做是不夠的：--perfect / --autoplay 會直接開局，
	# 那條路徑根本不會經過標題。改成 _ready 裡直接 await 三幀。
	await _warmup()
	# 網頁版的除錯旗標不走 OS.get_cmdline_user_args()（那個 API 在 web 匯出
	# 沒有實作），所以 web 上必須靠 query string 或直接呼叫。
	# 網址加 ?debug=audiodebug 即可。
	if _debug_audiodebug or _web_debug_flags().has("audiodebug"):
		# 延後幾幀再印：AudioServer 的 bus 要等 Sfx._ready() 建好
		await get_tree().process_frame
		await get_tree().process_frame
		Sfx.audio_debug()
		# 使用者點過畫面之後再印一次 —— 瀏覽器的 AudioContext
		# 只有在手勢之後才會真的 running，印一次看不出前後差異。
		_print_audio_again_later()
	if _autoplay:
		if unit_kinds.is_empty():
			unit_kinds = [KanaDB.Kind.SEION]
		_start_run()
	else:
		_enter_title()
	_open_test_page()


## 網頁版的除錯旗標走網址 query string：index.html?debug=audiodebug,shot=90
##
## 為什麼不能用命令列參數：OS.get_cmdline_user_args() 在 web 匯出的
## wasm 裡沒有實作（那個 API 只在原生平台有意義），回傳空陣列。
## 所以先前「在 web 版用 --flung 測試」其實從來沒生效過。
func _web_debug_flags() -> PackedStringArray:
	var out := PackedStringArray()
	if not OS.has_feature("web"):
		return out
	var js := JavaScriptBridge
	if js == null:
		return out
	var q: Variant = js.eval(
		"(new URLSearchParams(window.location.search)).get('debug') || ''", true)
	if q == null:
		return out
	for part in str(q).split(",", false):
		var t := str(part).strip_edges()
		if t != "":
			out.append(t)
	return out


func _print_audio_again_later() -> void:
	## 使用者點過畫面之後再印一次。
	## 網頁版的 AudioContext 在手勢之前一定是 suspended，
	## 印一次看不出「手勢之後變 running」這個關鍵變化。
	for i in range(6):
		await get_tree().create_timer(2.0).timeout
		print("[audio] === 第 %d 次檢查（使用者應該已經點過了）===" % (i + 1))
		Sfx.audio_debug()


func _open_test_page() -> void:
	match _test_page:
		"brief":
			_ui.show_brief()
		"dashboard":
			_ui.show_dashboard()
		"settings":
			_ui.show_settings(_ui.Page.TITLE)
		"levels":
			_ui.show_brief()
		"results":
			_ui.show_results({
				"cleared": true, "score": 24680, "correct": 44, "wrong": 2,
				"dodged": 0, "answered": 46, "best_combo": 31,
				"weakest": Srs.weakest(10), "slowest": Srs.slowest(4),
			})
		_:
			pass


func _parse_test_args() -> void:
	var next_is_shot := false
	for arg in OS.get_cmdline_user_args():
		if next_is_shot:
			_shot_frame = int(arg)
			next_is_shot = false
		elif arg == ARG_AUTOPLAY:
			_autoplay = true
		elif arg == "--perfect":
			_autoplay = true
			_autoplay_sabotage = false
		elif arg == "--miss":
			# 每題都故意撞錯，用來檢查錯題卡的排版與自動消失
			_autoplay = true
			_autoplay_sabotage = false
			_always_miss = true
		elif arg == "--holdmiss":
			_autoplay = true
			_autoplay_sabotage = false
			_always_miss = true
			_hold_miss = true
		elif arg == "--watch":
			# 持續檢查「三根石碑是否都在」，任何缺漏都印出上下文
			_watch = true
		elif arg == "--holdrelic":
			# 停在遺物／結算畫面，方便截圖檢查排版
			_autoplay = true
			_hold_relic = true
		elif arg == "--holdend":
			_autoplay = true
			_hold_end = true
		elif arg == "--relics":
			# 預先塞遺物，方便檢查 HUD 即時數值與心眼光暈
			_debug_relics = true
		elif arg == "--barrier":
			# 第一波就是橫桿障礙，方便直接截圖檢查外觀與判定
			_debug_barrier = true
		elif arg.begins_with("--zone="):
			# 直接跳到某一區，方便截圖檢查天色與橫幅
			_debug_zone = clampi(int(arg.substr(7)), 0, ZONES.size() - 1)
		elif arg == "--collapse":
			# 開局立刻體力用盡，方便截圖檢查跪倒動畫
			_debug_collapse = true
		elif arg == "--flung":
			# 開局立刻「撞到沒體力」，檢查被撞飛趴地的動畫
			_debug_flung = true
		elif arg == "--overdrive":
			# 開局直接進極限，檢查暗角、倍率、碑面閃爍
			_debug_overdrive = true
		elif arg == "--audiodebug":
			# 印出完整音訊狀態。網頁版「沒聲音」沒有任何錯誤訊息，
			# 沒有這份報告就只能靠猜。
			_debug_audiodebug = true
		elif arg == "--framestats":
			# 印出掉幀那一幀在做什麼，用來找頓頓的原因
			_framestats = true
		elif arg == "--kata":
			# 直接跑片假名單元，方便截圖與驗證
			unit_kinds = [KanaDB.Kind.KATA]
		elif arg == "--selftest":
			_run_selftest()
		elif arg.begins_with("--page="):
			_test_page = arg.substr(7)
		elif arg.begins_with("--qtype="):
			# 強制指定題型，方便逐一檢查各種題目的排版
			_forced_type = int(arg.substr(8))
		elif arg == ARG_SHOT:
			next_is_shot = true
		elif arg.begins_with(ARG_SHOT + "="):
			_shot_frame = int(arg.substr(ARG_SHOT.length() + 1))
		elif arg.begins_with(ARG_TURBO + "="):
			_turbo = clampf(float(arg.substr(ARG_TURBO.length() + 1)), 0.1, 60.0)
		elif arg.begins_with(ARG_TURBO):
			_turbo = clampf(float(arg.substr(ARG_TURBO.length())), 0.1, 60.0)
		elif arg.ends_with(".png"):
			_shot_path = arg


# ── 場景建構 ────────────────────────────────────────────────────────────
func _build_world() -> void:
	for l in SceneKit.build_lights(0):
		add_child(l)

	_track = load("res://src/game/track.gd").new() as Node3D
	_track.name = "Track"
	_track.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(_track)

	_runner = load("res://src/game/runner.gd").new() as Node3D
	_runner.name = "Runner"
	_runner.process_mode = Node.PROCESS_MODE_PAUSABLE
	# 跑者站在石碑前方一點，撞擊瞬間才不會被碑身完全遮住
	_runner.position = Vector3(0, 0, 1.6)
	add_child(_runner)

	# 主角補光：夜跑道裡保證角色輪廓永遠讀得出來
	_hero_light = OmniLight3D.new()
	_hero_light.light_color = Color(1.0, 0.90, 0.82)
	_hero_light.light_energy = 2.2
	_hero_light.omni_range = 9.0
	_hero_light.shadow_enabled = false
	_hero_light.position = Vector3(0.9, 3.0, 3.4)
	add_child(_hero_light)

	for i in LANE_COUNT:
		var s := load("res://src/game/monolith.gd").new() as Node3D
		s.name = "Stone%d" % i
		s.position = Vector3(LANE_X[i], 0, SPAWN_Z)
		s.process_mode = Node.PROCESS_MODE_PAUSABLE
		add_child(s)
		_stones.append(s)

	_build_barrier()
	_build_gem()

	# 題目語音（聽力題型）專用播放器
	_voice_player = AudioStreamPlayer.new()
	_voice_player.bus = "Sfx"
	# 見 Sfx._new_player：網頁版 Default 會落到 Sample，多 bus 時整局沒聲音。
	_voice_player.playback_type = AudioServer.PLAYBACK_TYPE_STREAM
	add_child(_voice_player)

	_cam = load("res://src/game/camera_director.gd").new() as Camera3D
	_cam.name = "Camera"
	_cam.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(_cam)
	_cam.make_current()

	# 全螢幕後製
	var post_layer := CanvasLayer.new()
	post_layer.layer = 1
	add_child(post_layer)
	var post := ColorRect.new()
	post.set_anchors_preset(Control.PRESET_FULL_RECT)
	post.mouse_filter = Control.MOUSE_FILTER_IGNORE
	post.color = Color.WHITE
	_post_mat = ShaderMaterial.new()
	_post_mat.shader = load(SceneKit.SHADER_POST)
	post.material = _post_mat
	post_layer.add_child(post)


func _build_barrier() -> void:
	_barrier = load("res://src/game/crossbar.gd").new() as Node3D
	_barrier.name = "Crossbar"
	_barrier.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(_barrier)


func _build_gem() -> void:
	_gem = Node3D.new()
	_gem.name = "Gem"
	_gem.visible = false

	_gem_core = MeshInstance3D.new()
	_gem_core.mesh = SceneKit.blob(0.30, 8, 12)
	_gem_core.material_override = SceneKit.glow_material(Color(0.55, 0.95, 0.85), 3.4)
	_gem_core.scale = Vector3(1, 1.25, 1)
	_gem.add_child(_gem_core)

	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.34
	torus.outer_radius = 0.42
	ring.mesh = torus
	ring.material_override = SceneKit.glow_material(Color(0.70, 1.0, 0.95), 2.4)
	ring.rotation_degrees = Vector3(90, 0, 0)
	_gem.add_child(ring)

	_gem_label = SceneKit.make_kana_label()
	_gem_label.font = FontKit.ui        # 顯示的是漢字，用 UI 字型
	_gem_label.font_size = 30
	_gem_label.pixel_size = 0.014
	_gem_label.position = Vector3(0, 0.60, 0)
	_gem_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_gem.add_child(_gem_label)

	var light := OmniLight3D.new()
	light.light_color = Color(0.55, 0.95, 0.85)
	light.light_energy = 1.8
	light.omni_range = 5.0
	_gem.add_child(light)


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 2
	layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(layer)

	_hud = load("res://src/ui/hud.gd").new() as Control
	_hud.set_anchors_preset(Control.PRESET_FULL_RECT)
	_hud.process_mode = Node.PROCESS_MODE_ALWAYS
	_hud.visible = false
	layer.add_child(_hud)

	_ui = load("res://src/ui/overlays.gd").new() as Control
	_ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	_ui.process_mode = Node.PROCESS_MODE_ALWAYS
	layer.add_child(_ui)


func _connect_ui() -> void:
	_ui.start_requested.connect(_on_start)
	_ui.resume_requested.connect(_on_resume)
	_ui.restart_requested.connect(_on_restart)
	_ui.quit_to_title.connect(_enter_title)
	_ui.relic_chosen.connect(_on_relic_chosen)
	_ui.settings_changed.connect(_apply_settings)
	_hud.lane_requested.connect(_go_lane)
	_hud.dodge_requested.connect(_do_dodge)


# ── 設定 ────────────────────────────────────────────────────────────────
func _apply_settings() -> void:
	_shake_user = float(SaveGame.get_setting("screen_shake", 1.0))
	_reduce_motion = float(SaveGame.get_setting("reduce_motion", 0.0))
	Curriculum.sync_settings()
	_cam.reduce_motion = _reduce_motion
	_post_mat.set_shader_parameter("reduce_motion", _reduce_motion)
	_post_mat.set_shader_parameter("grain", 0.045 * (1.0 - _reduce_motion * 0.7))
	_hud.set_hint_visible(DisplayServer.is_touchscreen_available() == false)


# ── 狀態切換 ────────────────────────────────────────────────────────────
func _enter_title() -> void:
	state = State.TITLE
	get_tree().paused = false
	Engine.time_scale = 1.0
	_hud.visible = false
	_runner.visible = true
	_gem.visible = false
	_gem_active = false
	for s in _stones:
		s.clear()
	_track.reset()
	_track.set_frozen(false)
	# 回到標題也要清掉天氣，否則會帶著上一局的下雨回主選單
	_zone = 0
	_apply_zone(false)
	_cam.reset()
	_title_orbit = 0.0
	_ui.show_title()
	Sfx.set_intensity(0.10)
	_apply_theme(0)
	_start_bgm()


## 背景音樂：優先用 res://audio/music 裡的音檔，沒有才用程序化配樂
func _start_bgm() -> void:
	if Sfx.has_external_bgm():
		if Sfx.bgm_track_name() == "":
			Sfx.set_bgm_track(randi() % 64)
	else:
		Sfx.music_on = true


func _on_start(kinds: Array) -> void:
	unit_kinds = kinds.duplicate() if not kinds.is_empty() else _tonight_kinds()
	_start_run()


## 標題上的「開始」不先選關。
## 還沒走出清音就只跑清音；已經碰過後面的音，就混進濁音和拗音。
## 具體抽哪些字由 SRS 決定，一輪長度固定。
func _tonight_kinds() -> Array:
	for kind in [KanaDB.Kind.DAKUON, KanaDB.Kind.YOON, KanaDB.Kind.KATA]:
		for entry in KanaDB.unit(kind):
			if int(SaveGame.kana_record(entry[0]).get("seen", 0)) > 0:
				return [KanaDB.Kind.SEION, KanaDB.Kind.DAKUON, KanaDB.Kind.YOON]
	return [KanaDB.Kind.SEION]


func _on_restart() -> void:
	_start_run()


## R 鍵：從任何進行中／結束的狀態直接跳回第一題。
##
## 這個函式存在的理由是「間距」。想要「再來一把」和真的在玩之間，
## 隔著選單就是兩次點擊，對已經有衝動的玩家來說足以讓他冷掉。
## 目標是按下去那一刻就已經在跑。
func _restart_now() -> void:
	# 倒在地上時不要立刻撿起來：那 1.9 秒的收尾是失敗的重量，
	# 拿掉它失敗就沒有後果感。倒地的 0.5 秒後才解禁。
	if state == State.COLLAPSE and _collapse_t < 0.5:
		return
	_start_run()


func _start_run() -> void:
	if unit_kinds.is_empty():
		unit_kinds = [KanaDB.Kind.SEION]
	_ui.hide_all()
	get_tree().paused = false
	Engine.time_scale = 1.0
	_time_scale_target = 1.0
	_hud.visible = true
	_hud.hide_explain()
	_hud.banner("", Color(1, 1, 1, 0), 0.0)
	_runner.visible = true
	_runner.reset()

	_stamina_cap = STAMINA_MAX + 40.0 * _relic_count("taiwa")
	_stamina = _stamina_cap
	_score = 0
	_chain = 0
	_best_chain = 0
	_overdrive = false
	_overdrive_t = 0.0
	_od_charge = 0.0
	_hud.set_overdrive(false)
	if _debug_overdrive:
		_chain = 12
		_begin_overdrive()
	_resolved = 0
	_relics = {}
	if _debug_relics:
		_relics = {"muga": 1, "taiwa": 2, "baigeki": 1, "denpatsu": 1}
	_next_relic_at = RELIC_EVERY
	_lane = 1
	_duck_timer = 0.0
	_wave_active = false
	_gap = 1.0
	_gem_active = false
	_gem.visible = false
	_gem_count = 0
	_obstacle_timer = 0
	_obstacle_wave = false
	_barrier.visible = false
	_zone = 0
	_sprint = 0.0
	_last_combo_milestone = 0
	_hud.clear_sprint()
	if _debug_barrier:
		_obstacle_timer = OBSTACLE_EVERY
	if _debug_zone >= 0:
		_check_zone()
	else:
		# 每局開頭都要重置天氣與天色，
		# 否則上一局的下雨會一路留到下一局
		_zone = 0
		_apply_zone(false)
	if _debug_collapse:
		# 在重設之後才把體力歸零，讓 _tick_play 走正常的體力用盡流程
		_stamina = 0.0
	if _debug_flung:
		_stamina = 0.0
		_debug_fling_pending = true
	_fades.clear()
	for s in _stones:
		s.clear()

	_cam.reset()
	_track.reset()
	_track.set_frozen(false)
	Srs.build_queue(unit_kinds)
	_apply_theme(int(unit_kinds[0]))
	_hud.set_unit(_unit_label())
	_hud.set_relics(_relics)
	_hud.set_progress(0, Srs.total_count())
	_hud.set_score(0)
	_hud.set_stamina(_stamina, _stamina_cap)
	_hud.set_timer(1.0)
	_hud.set_question({
		"prompt": "準備",
		"prompt_sub": "讀出正確的假名，撞破那座石碑",
		"type": 0,
	}, false)
	state = State.PLAY
	_pick_next_wave()


func _on_resume() -> void:
	if state != State.PAUSED:
		return
	_track.set_frozen(false)
	state = State.PLAY
	get_tree().paused = false
	_ui.hide_all()
	Engine.time_scale = 1.0


func _pause() -> void:
	if state != State.PLAY:
		return
	state = State.PAUSED
	_track.set_frozen(true)      # 暫停 = 時間暫停，地板也要停
	get_tree().paused = true
	_ui.show_pause()


func _unit_label() -> String:
	if unit_kinds.size() == 1:
		return KanaDB.UNIT_NAMES[unit_kinds[0]]
	if unit_kinds.size() >= 4:
		return "大滿貫"
	return "今夜一輪"


func _apply_theme(theme: int) -> void:
	_track.set_theme(theme)
	if _track.env != null:
		SceneKit.apply_palette(_track.env, _track.env.sky, theme)
	match theme:
		1:
			_post_mat.set_shader_parameter("tint", Color(1.06, 0.96, 0.94))
		2:
			_post_mat.set_shader_parameter("tint", Color(0.94, 0.98, 1.08))
		_:
			_post_mat.set_shader_parameter("tint", Color(1, 1, 1))


# ── 波次 ────────────────────────────────────────────────────────────────
func _pick_next_wave() -> void:
	# 每 OBSTACLE_EVERY 題插入一個「障礙波」：只有橫桿，沒有題目。
	# 讓跑動有第二種動作（純物理反應），也讓閃避不再是死機制。
	if _obstacle_timer >= OBSTACLE_EVERY:
		_spawn_obstacle_wave()
		return

	_obstacle_wave = false
	_barrier.visible = false
	var kana := Srs.pop_next()
	if kana == "":
		_finish(true)
		return

	_question = Curriculum.make_question(kana, Srs.progress(), _forced_type)
	# 石碑是三個節點循環重用的。任何「上一波才排定的延遲清除」都會打到
	# 新一波的同一顆石碑上，讓畫面少一根。出新波時一律作廢。
	_fades.clear()
	_wave_z = SPAWN_Z
	_wave_active = true
	_legible_time = 0.0
	_duck_timer = 0.0

	var answers: Array = _question["choices"]
	var sources: Array = _question["choice_source"]
	var is_kana: bool = _question["choice_kind"] == "kana"
	var target := int(_question["target_index"])

	for i in LANE_COUNT:
		var stone: Node3D = _stones[i]
		stone.position = Vector3(LANE_X[i], 0, _wave_z)
		stone.rotation = Vector3.ZERO
		stone.scale = Vector3.ONE
		stone.set_speed_hint(_speed01())
		stone.setup(str(answers[i]), i == target, is_kana, KanaDB.romaji(str(sources[i])))

	_hud.set_question(_question, false)
	_hud.hide_explain()                 # 新題目一出來，錯題卡就收掉
	_hud.set_progress(Srs.done(), Srs.total_count())
	# 三級評價的說明只在一局的頭幾題出現，之後自動收起
	_hud.set_grade_hint(_resolved < 5)
	_track.set_speed01(_speed01())
	_maybe_spawn_gem()
	_play_question_voice()
	_obstacle_timer += 1
	# 極限下石碑一閃就滅：閱讀時間被壓到 55%，
	# 逼玩家在還沒看清楚就必須決定要不要出手
	if _overdrive:
		for s in _stones:
			s.set_legible_window(OVERDRIVE_LEGIBLE)


## 障礙波：沒有題目，只有橫桿。
##
## 這裡刻意不排題：橫桿擋住兩條道、留一條綠色空道，如果同時還要答題，
## 「躲得過橫桿」和「站在答對的跑道」兩個目標會互相衝突，
## 玩家每一波都必須二選一 —— 那不是選擇，是懲罰。實測過之後
## 完美跑者每局會因此多錯 5 題。
##
## 所以障礙波是純粹的「走位 + 可選閃避」節拍：
##   綠色空道站著直接過（最佳，回復體力）
##   紅白條上蹲下也能過，但扣體力、不計分
##   紅白條上不蹲 → 撞飛
## 結論是閃避不再是「哪條道都能無腦按」，因為留一條空道在等著你換過去。
func _spawn_obstacle_wave() -> void:
	_obstacle_timer = 0
	_obstacle_wave = true
	_question = {}
	_fades.clear()
	_wave_z = SPAWN_Z
	_wave_active = true
	_legible_time = 0.0
	_duck_timer = 0.0
	_barrier.setup(_barrier_blocked(_resolved), LANE_X)
	_barrier.position.z = _wave_z
	for s in _stones:
		s.clear()
	_hud.set_question(_question, false)
	_hud.hide_explain()
	_hud.set_barrier_hint(_barrier_blocked(_resolved))
	_hud.set_timer(1.0, false)


## 每次挑一組被擋的走道。三條都擋等於沒有選擇，所以固定留一條空的。
## 用題序當種子，讓同一局的配置固定，除錯時好重現。
func _barrier_blocked(seed_val: int) -> int:
	var open_lane := (seed_val * 7 + 3) % LANE_COUNT
	var mask := 0
	for i in LANE_COUNT:
		if i != open_lane:
			mask |= 1 << i
	return mask


## 依照已答題數切換分區：跳橫幅、換天色天氣、給該區的 twist。
func _check_zone() -> void:
	if _debug_zone >= 0:
		_zone = _debug_zone
		_apply_zone()
		return
	var z := clampi(_resolved / ZONE_LEN, 0, ZONES.size() - 1)
	if z == _zone:
		return
	_zone = z
	_apply_zone()
	# 換區接一小段衝刺。進最後一區改成長衝刺，這一輪的結尾就在那裡。
	if z > 0 and _resolved % ZONE_LEN == 0:
		if z >= ZONES.size() - 1:
			_start_sprint(9.0, "最後衝刺　得分 ×2")
		else:
			_start_sprint()


## 強制把目前區域的設定套回去。
##
## 少了這一步就會出現「一旦下雨就永遠在下雨」：開局時 _zone 已經是 0，
## _check_zone() 會提早 return，於是 _apply_zone() 從沒被呼叫過，
## 上一局的天氣就這樣留到下一局。
func _apply_zone(show := true) -> void:
	var d: Dictionary = ZONES[_zone]
	_fog_target = d["fog"]
	_fog_density_target = d["density"]
	_track.set_weather(str(d["twist"]), d["weather"], d["petal"])
	Sfx.set_weather(str(d["twist"]))
	# 直接套用，不漸變，方便截圖
	if _track.env != null:
		_track.env.fog_light_color = _fog_target
		_track.env.fog_density = _fog_density_target
	if show:
		_hud.banner_zone(str(d["title"]), str(d["place"]), str(d["note"]))
		Sfx.zone_change(_zone)


func _start_sprint(duration := SPRINT_TIME, text := "衝刺！得分 ×2") -> void:
	_sprint = duration
	_track.set_speed01(1.0)
	_hud.set_sprint(true)
	_hud.banner(text, UiKit.GOLD, 1.0)
	_cam.punch(0.8 * _shake_user)
	Sfx.sprint()


## 天色與天氣每幀往目標插值，換區時是漸變而不是突然跳色
func _blend_zone(delta: float) -> void:
	var env: Environment = _track.env
	if env == null:
		return
	var k := clampf(delta * 0.9, 0.0, 1.0)
	env.fog_light_color = env.fog_light_color.lerp(_fog_target, k)
	env.fog_density = lerpf(env.fog_density, _fog_density_target, k)


func _advance_barrier(dt: float) -> void:
	_wave_z += _speed * dt
	_barrier.position.z = _wave_z
	for i in LANE_COUNT:
		_stones[i].position.z = _wave_z

	if _wave_z < LEGIBLE_Z:
		_legible_time = 0.0
	else:
		_legible_time += dt
		var remain := clampf(_wave_z / LEGIBLE_Z, 0.0, 1.0)
		_hud.set_timer(remain, remain < 0.34)

	if _wave_z >= 0.0:
		_resolve_barrier()


## 障礙波的判定：只看橫桿，不涉及題目。
func _resolve_barrier() -> void:
	_wave_active = false
	var blocked_here: bool = bool(_barrier.blocks(_lane))
	var lane := _lane

	if blocked_here and _duck_timer > 0.0:
		# 蹲過了，但有代價：扣體力、不計分。閃避不是免費的。
		_barrier.mark_cleared(lane)
		_stamina = maxf(0.0, _stamina - STAMINA_DODGE)
		Sfx.dodge()
		Srs.session_dodged += 1
		_hud.banner("蹲過了 −%d 體力" % int(STAMINA_DODGE), Color(0.95, 0.70, 0.35), 0.8)
		_cam.punch(0.5 * _shake_user)
	elif not blocked_here:
		# 綠色空道站著直接過 —— 這是最佳解
		_barrier.mark_cleared(lane)
		_score += int(round(40.0 + _speed * 1.2))
		_stamina = minf(_stamina_cap, _stamina + 5.0)
		Sfx.dodge()
		Srs.session_dodged += 1
		_hud.banner("通過 +%d 體力" % 5, Color(0.45, 0.95, 0.80), 0.7)
		_cam.punch(0.4 * _shake_user)
		_cam.shake(0.2 * _shake_user, 3.5)
	else:
		# 被擋又沒蹲 → 撞飛
		_barrier.mark_hit(lane)
		_stamina = maxf(0.0, _stamina - 18.0)
		_chain = 0
		_runner.burst()
		_cam.shake(0.85 * _shake_user, 8.0)
		_cam.punch(0.9 * _shake_user)
		_hud.banner("撞到！", Color(1.0, 0.42, 0.42), 0.7)
		_damage_flash = 1.0
		Sfx.miss()

	_duck_timer = 0.0
	_runner.set_duck(false)
	_barrier.position.z = -400.0      # 立刻收掉，別停在畫面上
	_gap = 0.44
	if _stamina <= 0.0:
		_begin_collapse(true)
		return
	_check_after_gap()


## 題目的語音。聽力題是一個假名；單字題是整詞錄音那一段。
func _play_question_voice() -> void:
	if _voice_player == null:
		return
	if _question.has("audio"):
		_play_clip(str(_question["audio"]))
		return
	if _question.has("word_audio"):
		_play_word_voice(_question["word_audio"])


func _play_clip(path: String) -> void:
	if path == "" or not ResourceLoader.exists(path):
		return
	var stream := load(path) as AudioStream
	if stream == null:
		return
	_voice_player.stream = stream
	_voice_player.volume_db = 0.0
	_voice_player.play()


## 依序播放單詞讀音。
##
## 必須等前一段「播完」才能接下一段。
## 原本固定等 0.1 秒就換 —— 但同一個 player 換 stream 會把前一段截斷，
## 三個音疊在一起等於只聽得到最後一個（りゆう 只剩 う），
## 聽起來像在提示一個錯的假名。
func _play_word_voice(paths: Array) -> void:
	if paths.is_empty() or _voice_player == null or not is_inside_tree():
		return
	for p in paths:
		if not is_inside_tree() or state != State.PLAY:
			return
		var path := str(p)
		if path == "" or not ResourceLoader.exists(path):
			continue
		var stream := load(path) as AudioStream
		if stream == null:
			continue
		_voice_player.stream = stream
		_voice_player.volume_db = 0.0
		_voice_player.play()
		# 等這一段真的結束（0.04 秒的極短下限，避免單音的字重複觸發）
		await _voice_player.finished
		if not is_inside_tree() or state != State.PLAY:
			return
		await get_tree().create_timer(0.04, true, false, true).timeout


func _speed01() -> float:
	return clampf(remap(_speed, SPEED_MIN, SPEED_MAX, 0.0, 1.0), 0.0, 1.0)


func _current_speed() -> float:
	# 速度跟這一輪打得有多熱走，不跟課表進度走。失手連段歸零，速度就落下來。
	var heat := clampf(float(_chain) / 16.0, 0.0, 1.0)
	var base := lerpf(SPEED_MIN, SPEED_MAX * 0.92, heat)
	if _zone >= ZONES.size() - 1:
		base = maxf(base, SPEED_MAX * 0.78)
	var v := base * (1.0 + 0.15 * _relic_count("baigeki"))
	if _sprint > 0.0:
		v *= SPRINT_BOOST
	if _overdrive:
		v = maxf(v, SPEED_MAX * 0.72)
		v *= OVERDRIVE_BOOST
	return v


# ── 每幀 ────────────────────────────────────────────────────────────────
func _process(delta: float) -> void:
	InputKit.begin_frame()
	_frames += 1
	if _framestats:
		_frame_probe(delta)
	if _shot_frame > 0 and _frames == _shot_frame:
		_capture_and_quit()
		return
	if _turbo != 1.0:
		delta *= _turbo
	_watch_stones(delta)

	# 打擊停滯：答對瞬間的靜止，是打擊感的來源。
	# 用真實時鐘計時 —— 用 scaled delta 的話，停滯長度會跟畫面時率，
	# 60Hz 和 120Hz 的手機感受完全不同。
	if _hitstop_until_ms > Time.get_ticks_msec():
		Engine.time_scale = 0.06
	else:
		_hitstop_until_ms = 0
		Engine.time_scale = lerpf(Engine.time_scale, _time_scale_target,
			clampf(delta * 14.0, 0.0, 1.0))
		if absf(Engine.time_scale - 1.0) < 0.004:
			Engine.time_scale = 1.0

	if not get_tree().paused:
		_advance_fades(delta)

	# R 立即重開：任何非標題狀態都吃這個鍵。
	# 為什麼要獨立於 _handle_input：那一支只在 PLAY 裡呼叫，
	# 而最需要「秒回下一把」的兩個時刻（倒在地上、結算畫面）都不是 PLAY。
	if Input.is_action_just_pressed("restart") and state != State.TITLE:
		_restart_now()
		return

	match state:
		State.PLAY:
			_tick_play(delta)
		State.COLLAPSE:
			_tick_collapse(delta)
		State.TITLE:
			_tick_title(delta)
		State.RELIC:
			if _autoplay and not _hold_relic:
				_bot_pick_relic()
		State.RESULTS:
			if _autoplay and not _hold_end:
				if _framestats:
					print("[frame] total=%d slow(>28ms)=%d slowest=%.1fms" % [
						_total, _slow_frames, _slowest])
				print("[kana-run] run finished: score=%d answered=%d/%d correct=%d wrong=%d dodged=%d combo=%d stamina=%.0f" % [
					_score, Srs.answered_this_run(), Srs.total_count(),
					Srs.session_correct, Srs.session_wrong, Srs.session_dodged,
					_best_chain, _stamina])
				if _watch:
					print("[watch] missing %d frames total, longest run %d frames" % [_watch_violations, _watch_longest])
				get_tree().quit()
		_:
			pass

	_update_post(delta)


func _bot_pick_relic() -> void:
	var options := RelicPool.roll(_relics)
	if options.is_empty():
		state = State.PLAY
		get_tree().paused = false
		return
	_on_relic_chosen(str(options[0]["id"]))


func _tick_play(delta: float) -> void:
	# Godot 傳給 _process 的 delta 已經乘過 Engine.time_scale，
	# 不要再乘一次 —— 否則打擊停滯會變成兩倍深度，整個節奏都會跑掉。
	var dt := delta

	_handle_input()
	if _autoplay:
		_autopilot()

	_speed = _current_speed()
	var dist := _speed * dt
	_track.advance(dist)
	_runner.speed01 = _speed01()
	_runner.set_duck(_duck_timer > 0.0)
	_tick_duck(dt)
	_cam.speed01 = _speed01()
	_cam.follow(_runner.position.x, dt)
	_hero_light.position.x = _runner.position.x * 0.6 + 0.9
	Sfx.set_wind(_speed01(), delta)
	# 極限要在每幀檢查：連段是答對時 +1、答錯時歸零，
	# 兩個事件都不在這裡，所以不能只在 _resolve_hit 裡判斷
	_tick_overdrive(dt)
	# 配樂強度跟「張力」走：速度 + 連段 + 衝刺關 + 目前區域
	var tension := _speed01() * 0.45 + float(_chain) * 0.02 + (0.2 if _sprint > 0.0 else 0.0)
	# 極限直接把配樂推到滿：這個狀態的聽覺辨識度必須比視覺更高，
	# 玩家在亂掉的時候要能只靠耳朵就知道自己正在極限裡
	if _overdrive:
		tension = maxf(tension, 0.9)
	Sfx.set_intensity(clampf(tension + float(_zone) * 0.06, 0.0, 1.0))
	_blend_zone(delta)
	if _sprint > 0.0:
		_sprint = maxf(0.0, _sprint - dt)
		if _sprint == 0.0:
			_hud.clear_sprint()
	_advance_gem(dt)
	# 障礙波不扣體力：它本來就是兩組題目之間的喘息，
	# 若照常扣，額外插入的九次穿越會把體力抽乾（一局 46 題只回 8 次血）。
	if not _obstacle_wave:
		_drain_stamina(dt)
	if _stamina <= 0.0:
		_begin_collapse(_debug_fling_pending)
		_debug_fling_pending = false
		return

	if _wave_active:
		_advance_wave(dt)
	else:
		_gap -= dt
		if _gap <= 0.0:
			_check_after_gap()
			if state == State.PLAY:
				_pick_next_wave()

	_hud.set_stamina(_stamina, _stamina_cap)
	_hud.set_score(_score)
	_hud.set_speed_kmh(int(round(40.0 + _speed01() * 120.0)))
	_hud.set_combo(_combo_mult(), _chain)
	_tick_relic_status()

## 遺物圖示的即時數值。6Hz 足夠，玩家眼睛跟不上更高的更新率。
var _relic_status_t := 0.0
var _gem_count := 0
var _debug_relics := false
var _debug_barrier := false
var _collapse_t := 0.0
var _collapse_flung := false
var _dollied := false
var _debug_zone := -1
var _debug_collapse := false
var _debug_flung := false

# ── 掉幀量測（--framestats）────────────────────────────────────────────
# 玩家回報「左右切換跑道時偶爾會頓一下」。與其猜測哪一段在打架，
# 直接記錄掉幀的那一幀正在做什麼：換線、換波、殘影清除、遺物 UI。
# 只在 --framestats 時啟用，一般遊玩沒有任何成本。
var _framestats := false
var _prev_lane := -1
var _slowest := 0.0
var _slow_frames := 0
var _total := 0

func _frame_probe(delta: float) -> void:
	_total += 1
	var ms := delta * 1000.0
	# 只記錄明顯超出單幀預算的情況
	if ms < 28.0:
		return
	_slow_frames += 1
	if ms <= _slowest:
		return
	_slowest = ms
	print("[frame] %.1fms  state=%d lane=%d->%d wave_z=%.1f resolved=%d fades=%d duck=%.2f" % [
		ms, state, _prev_lane, _lane, _wave_z, _resolved, _fades.size(), _duck_timer])
	_prev_lane = _lane
var _debug_fling_pending := false
var _debug_overdrive := false
var _debug_audiodebug := false

func _tick_relic_status() -> void:
	_relic_status_t -= get_process_delta_time()
	if _relic_status_t > 0.0:
		return
	_relic_status_t = 0.16
	_hud.set_relic_status({
		"stamina_cap": int(_stamina_cap),
		"heal": int(STAMINA_HEAL * (1.0 + 0.5 * _relic_count("juugo"))),
		"mult": pow(1.55, _relic_count("baigeki")),
		"speed_bonus": 0.15 * _relic_count("baigeki"),
		"perfect_ms": int(450.0 * (1.0 + 0.45 * _relic_count("denpatsu"))),
		"combo_top": 3.0 + 1.0 * _relic_count("mugen"),
		"drain_cut": 0.35 * _relic_count("jikyuu"),
		"gems": _gem_count,
		"muga_on": _relic_count("muga") > 0,
	})


## 體力用盡：不要直接跳結算，先讓角色跪下來、跑道停下來。
## 直接切畫面會讓失敗沒有重量，節奏也收不住。
##
## flung=true 代表「是撞到沒體力」而不是慢慢耗盡：
## 角色會被撞飛出去，趴在地上。
func _begin_collapse(flung := false) -> void:
	if state != State.PLAY:
		return
	state = State.COLLAPSE
	_collapse_t = 0.0
	_collapse_flung = flung
	_dollied = false
	_wave_active = false
	_duck_timer = 0.0
	_runner.set_duck(false)
	_runner.collapse(flung)
	_speed = 0.0
	_time_scale_target = 1.0
	_hitstop_until_ms = 0
	_hud.hide_explain()
	_hud.set_timer(1.0, false)
	_cam.shake(0.35 * _shake_user, 3.0)
	for s in _stones:
		s.fade_out(0.5)
	_track.set_frozen(true)
	# 倒地時石碑恢復正常長度的可讀窗口，不然極限的淡出會殘留在下一局
	for s in _stones:
		s.set_legible_window(1.0)
	_hud.set_overdrive(false)
	_overdrive = false
	Sfx.set_wind(0.0, 1.0)
	# 被撞飛時先不要推近鏡頭 —— 鏡頭一推近，「往前飛出去」就變成
	# 「在原地倒下」，反而看不出被撞。落地之後再推近看趴著的姿勢。
	_cam.set_dolly(not flung)
	if flung:
		_hud.banner("撞飛出去了", UiKit.INK_DIM, 1.4)
		Sfx.miss()
		_cam.shake(1.0 * _shake_user, 6.0)
		_cam.punch(1.2 * _shake_user)
		_damage_flash = 1.0
	else:
		_hud.banner("體力用盡", UiKit.INK_DIM, 1.4)
		Sfx.miss()


## 跪倒動畫約 1.4 秒，跑道同時停下來，之後才進結算
func _tick_collapse(delta: float) -> void:
	_collapse_t += delta
	var k := clampf(_collapse_t / 1.4, 0.0, 1.0)
	# 跑道要「停下來」，不是慢慢滑行。減速集中在前 0.45 秒，
	# 之後完全不推進 —— 否則角色已經倒地，路面卻還在往後捲。
	# 被撞飛時角色會往前衝出去，跑道要等她落地才真的停住，
	# 否則畫面上會出現「人已經飛出去了，路面還在加速」的怪異畫面。
	if _collapse_flung and _collapse_t < 0.55:
		_speed = maxf(0.0, _speed - 26.0 * delta)
		_track.advance(_speed * delta)
	else:
		if k < 0.34:
			_speed = lerpf(_speed, 0.0, clampf(delta * 9.0, 0.0, 1.0))
			_track.advance(_speed * delta)
		else:
			_speed = 0.0
	_track.set_speed01(0.0)
	_cam.speed01 = 0.0
	_cam.follow(_runner.position.x, delta)
	# 鏡頭追著飛出去的位移走，不然 5.6 公尺的距離差會讓角色縮成一個小點，
	# 看起來像「跑掉了」而不是「被撞飛」。
	if _collapse_flung and _collapse_t < 0.72:
		_cam.follow_flight(_runner.position.z, _runner.position.y, delta)
	# 落地之後才推近鏡頭去看趴著的姿勢
	if _collapse_flung and _collapse_t >= 0.62 and not _dollied:
		_dollied = true
		_cam.set_dolly(true)
	if _collapse_t >= 1.9:
		_finish(false)


## ── 暖機 ──────────────────────────────────────────────────────────────
## 量測結果：整局 17,509 幀裡只有 1 幀超過 28ms，而且是在第一幀（133ms）。
## 那是一次性的資源上傳 —— 題卡、錯題卡、遺物晶片、石碑、橫桿的材質
## 與字型圖集都在第一次繪製時才建立。開局前先各畫一次，
## 玩家按「開始挑戰」之後就不會再遇到這一下頓挫。
func _warmup() -> void:
	var saved_hud := _hud.visible
	_hud.visible = true
	for s in _stones:
		s.setup("あ", false, true, "a")
	_barrier.setup(_barrier_blocked(0), LANE_X)
	_barrier.position.z = -30.0
	_hud.set_barrier_hint(_barrier_blocked(0))
	_hud.show_explain({"kana": "あ", "romaji": "a", "lines": ["あ行母音"], "confusions": []})
	_hud.set_relics({"muga": 1, "baigeki": 1})
	_hud.set_relic_status({"stamina_cap": 100, "mult": 1.0})
	_hud.banner_zone("第一區", "草木", "先熟悉節奏")
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	for s in _stones:
		s.clear()
	_barrier.visible = false
	_hud.hide_explain()
	_hud.set_relics({})
	_hud.hide_zone()
	_hud.visible = saved_hud


func _tick_title(delta: float) -> void:
	# 標題畫面也要有生命：慢速空跑 + 相機緩繞
	var dt := delta * Engine.time_scale
	_track.advance(TITLE_SPEED * dt)
	_track.set_speed01(0.18)
	_runner.speed01 = 0.22
	_title_orbit += dt * 0.18
	_cam.speed01 = 0.10
	_cam.position = _cam.position.lerp(
		Vector3(sin(_title_orbit) * 3.4, 3.0 + sin(_title_orbit * 0.7) * 0.5, 9.4),
		clampf(delta * 2.0, 0.0, 1.0))
	Sfx.set_wind(0.12, delta)


func _advance_fades(delta: float) -> void:
	var i := _fades.size() - 1
	while i >= 0:
		var entry: Array = _fades[i]
		entry[1] = float(entry[1]) - delta
		if float(entry[1]) <= 0.0:
			var node: Node3D = entry[0]
			node.dbg_tag = "fades_delay_done"
			# 碎石塊還在飛的話就等它自己落地消失（SHATTER_LIFE）
			if not (node.broken and node.shattering()):
				node.clear()
				_fades.remove_at(i)
			else:
				entry[1] = 0.5
		i -= 1


func _drain_stamina(dt: float) -> void:
	# 節奏設計：答對淨賺一點，答錯一次約當 5 題的進帳。
	# 打得準的人體力會一直是滿的，失手 5～6 次就會出局。
	var rate := (1.7 + _speed * 0.05) * (1.0 - 0.35 * _relic_count("jikyuu"))
	# 極限的體力代價：貪 ×3 的同時血也在掉。
	# 這個交換是極限的全部重點 —— 沒有代價就只是白送分數，
	# 玩家會無腦待著，不會有「再撐三題」的念頭。
	if _overdrive:
		rate *= OVERDRIVE_DRAIN
	_stamina = maxf(0.0, _stamina - rate * dt)


func _advance_wave(dt: float) -> void:
	# 用明確的旗標判斷，不要看 _barrier.visible ——
	# 橫桿通過後會被隱藏，靠可見性推斷會讓後續題目波全部走錯分支。
	if _obstacle_wave:
		_advance_barrier(dt)
		return
	_wave_z += _speed * dt
	for i in LANE_COUNT:
		_stones[i].position.z = _wave_z

	if _wave_z < LEGIBLE_Z:
		_legible_time = 0.0
	else:
		_legible_time += dt
		var remain := clampf(_wave_z / LEGIBLE_Z, 0.0, 1.0)
		_hud.set_timer(remain, remain < 0.34)

	if _wave_z >= 0.0:
		_resolve_impact()


func _update_post(delta: float) -> void:
	_post_mat.set_shader_parameter("speed_blur", _speed01() * 0.30 * (1.0 - _reduce_motion * 0.8))
	_post_mat.set_shader_parameter("aberration", 1.0 + _speed01() * 2.2)
	_damage_flash = maxf(0.0, _damage_flash - delta * 2.4)
	_good_flash = maxf(0.0, _good_flash - delta * 3.0)
	_post_mat.set_shader_parameter("damage", _damage_flash)
	_post_mat.set_shader_parameter("flash", _good_flash * 0.26)
	_post_mat.set_shader_parameter("flash_color", Color(1.0, 0.95, 0.80, 1.0))
	_post_mat.set_shader_parameter("focus_pulse", _cam.focus() if state == State.PLAY else 0.0)


# ── 輸入 ────────────────────────────────────────────────────────────────
func _handle_input() -> void:
	if Input.is_action_just_pressed("pause"):
		_pause()
		return
	# R 直接重開由 _process 統一處理（PLAY／COLLAPSE／RESULTS 都吃），
	# 這裡不再重複判定 —— 同一幀呼叫兩次會讓 _start_run 跑兩遍。
	if Input.is_action_just_pressed("lane_left"):
		_go_lane(_lane - 1)
	elif Input.is_action_just_pressed("lane_right"):
		_go_lane(_lane + 1)
	elif Input.is_action_just_pressed("pick_1"):
		_go_lane(0)
	elif Input.is_action_just_pressed("pick_2"):
		_go_lane(1)
	elif Input.is_action_just_pressed("pick_3"):
		_go_lane(2)
	# 一幀只做一個動作。觸控裝置常常把同一次手勢同時送成按鍵事件與觸控事件，
	# 若兩個來源各自呼叫一次，就會出現「下滑聽到兩聲」的問題。
	# 閃避也涵蓋鍵盤的 ↓ / S / X —— 那些按鍵雖然早就註冊進 InputMap，
	# 之前卻從來沒有人查過，所以按鍵完全沒反應。
	var acted := false
	if Input.is_action_just_pressed("dodge") or InputKit.dodge_pressed \
			or InputKit.tapped_swiped_down:
		_do_dodge()
		acted = true
	if InputKit.swipe_dir != 0:
		_go_lane(_lane + InputKit.swipe_dir)
		acted = true
	if InputKit.tapped and not acted:
		_tap_screen(InputKit.tap_position)


## 點螢幕左右三分之一換道，中間不反應（避免誤觸）
func _tap_screen(pos: Vector2) -> void:
	var w := float(get_viewport().get_visible_rect().size.x)
	if w <= 0.0:
		return
	var r := pos.x / w
	if r < 0.34:
		_go_lane(_lane - 1)
	elif r > 0.66:
		_go_lane(_lane + 1)


func _go_lane(target: int) -> void:
	if state != State.PLAY:
		return
	var t := clampi(target, 0, LANE_COUNT - 1)
	if t == _lane:
		return
	_lane = t
	_runner.set_lane(LANE_X[_lane])
	Sfx.lane_shift()


func _do_dodge() -> void:
	if state != State.PLAY or not _wave_active:
		return
	_duck_timer = DODGE_WINDOW
	_runner.set_duck(true)
	Sfx.dodge()
	_cam.punch(0.35 * _shake_user)


## 閃避有時限：原本 _duck_timer 設定後從來沒有遞減，
## 所以在障礙波裡只要按一次，整段路都保持著蹲姿，毫無技術可言。
func _tick_duck(dt: float) -> void:
	if _duck_timer <= 0.0:
		return
	_duck_timer = maxf(0.0, _duck_timer - dt)
	if _duck_timer == 0.0 and not _obstacle_wave:
		_runner.set_duck(false)


# ── 判定 ────────────────────────────────────────────────────────────────
func _resolve_impact() -> void:
	_wave_active = false
	_resolve_impact_body()


## 題目的判定本體，障礙波與一般題目波共用。
func _resolve_impact_body() -> void:
	var kana: String = _question["kana"]
	var ms := _legible_time * 1000.0

	if _duck_timer > 0.0:
		_resolve_dodge(kana)
	elif _lane == int(_question["target_index"]):
		_resolve_hit(kana, ms)
	else:
		_resolve_miss(kana, ms)


func _grade(ms: float) -> String:
	var perfect := 450.0 * (1.0 + 0.45 * _relic_count("denpatsu"))
	var great := 900.0 * (1.0 + 0.25 * _relic_count("denpatsu"))
	if ms <= perfect:
		return "perfect"
	if ms <= great:
		return "great"
	return "good"


func _combo_mult() -> float:
	var top := 3.0 + 1.0 * _relic_count("mugen")
	# 第三區「神社」的 twist：連段爬得更快，獎勵一路連到底
	var step := 0.08 * (1.0 + (0.5 * _relic_count("mugen")))
	if _zone_twist() == "combo":
		step *= 2.0
	var v := 1.0 + float(_chain) * step
	if _sprint > 0.0:
		v *= SPRINT_MULT
	if _overdrive:
		v *= OVERDRIVE_MULT
	# 極限要能蓋過連段倍率的天花板，否則倍率封頂之後
	# 極限的「×3」只是看起來好看，實際上不會比後段多賺
	return clampf(v, 1.0, top * 2.0 * (OVERDRIVE_MULT if _overdrive else 1.0))


func _zone_twist() -> String:
	return str(ZONES[clampi(_zone, 0, ZONES.size() - 1)]["twist"])


## 熱度累滿就爆開固定的幾秒，不是連段卡在 30 才永久加速。
## 爆開期間體力掉得更快，撐過這段就是這一輪的高潮。
func _tick_overdrive(delta: float) -> void:
	if not _overdrive:
		return
	_overdrive_t += delta
	if _overdrive_t >= OVERDRIVE_TIME:
		_end_overdrive()


func _note_heat(grade: String) -> void:
	if _overdrive:
		return
	_od_charge += 1.6 if grade == "perfect" else 1.0
	if _od_charge >= OVERDRIVE_NEED:
		_begin_overdrive()


func _begin_overdrive() -> void:
	_overdrive = true
	_overdrive_t = 0.0
	_od_charge = 0.0
	_hud.banner("極限　×3", UiKit.GOLD, 1.6)
	_hud.set_overdrive(true)
	_cam.pulse(1.0)
	_cam.punch(0.9 * _shake_user)
	_track.flash_rails()
	Sfx.set_intensity(1.0)
	Sfx.hit_perfect()


func _end_overdrive() -> void:
	if not _overdrive:
		return
	_overdrive = false
	_overdrive_t = 0.0
	_hud.banner("極限結束", UiKit.INK_DIM, 0.9)
	_hud.set_overdrive(false)


## 每 10 連段做一次場面：倍率上限體感、光環、路面提示
func _check_combo_milestone() -> void:
	var step := 10
	if _chain <= 0 or _chain % step != 0 or _chain == _last_combo_milestone:
		return
	_last_combo_milestone = _chain
	_hud.banner("%d 連！" % _chain, UiKit.JADE, 0.9)
	_cam.pulse(1.0)
	_cam.punch(0.7 * _shake_user)
	_track.flash_rails()


func _resolve_hit(kana: String, ms: float) -> void:
	var target := int(_question["target_index"])
	var stone: Node3D = _stones[target]
	# 撞擊點 = 跑者當下的 x，讓碎石朝鏡頭與玩家側炸開
	var lane_x := stone.position.x
	if _runner != null:
		lane_x = (stone.position.x + _runner.position.x) * 0.5
	stone.smash(lane_x)
	_runner.burst()
	_runner.guard()

	var grade := _grade(ms)
	var mult := _combo_mult()
	var base := 60.0 + _speed * 1.2
	var time_bonus: float = {"perfect": 200.0, "great": 120.0, "good": 60.0}.get(grade, 20.0)
	var gained := int(round((base + time_bonus) * mult))
	gained = int(round(float(gained) * pow(1.55, _relic_count("baigeki"))))

	_score += gained
	_chain += 1
	_best_chain = maxi(_best_chain, _chain)
	_resolved += 1
	_stamina = minf(_stamina_cap, _stamina + STAMINA_HEAL * (1.0 + 0.5 * _relic_count("juugo")))
	Srs.record(kana, 1, ms)
	_check_combo_milestone()
	_check_zone()
	_note_heat(grade)

	_good_flash = 1.0
	_hitstop_until_ms = Time.get_ticks_msec() + 90
	_cam.pulse(1.0)
	_cam.shake(0.45 * _shake_user, 6.0)
	_cam.punch(0.5 * _shake_user)

	match grade:
		"perfect":
			Sfx.hit_perfect()
			_hud.banner("PERFECT +%d" % gained, UiKit.GOLD, 0.7)
		"great":
			Sfx.hit_good()
			_hud.banner("GREAT +%d" % gained, UiKit.JADE, 0.65)
		_:
			Sfx.hit_good()
			# 原本只顯示加分，玩家看不到其實有第三級評價。
			# 三級都秀出來，PERFECT / GREAT 才有存在意義。
			_hud.banner("GOOD +%d" % gained, Color(0.72, 0.78, 0.92), 0.6)

	_hud.set_question(_question, true)
	_after_resolve(stone, 0.30)
	_gap = 0.42


func _resolve_miss(kana: String, ms: float) -> void:
	var stone: Node3D = _stones[_lane]
	# 撞錯的那顆石碑不是淡出，而是真的砸過來。
	# 原本只是 fade_out，玩家感受不到「失敗的重量」——
	# 撞碎之後碎塊朝鏡頭飛過來，失敗就變成一個看得見的場面。
	stone.crush(_runner.position.x)
	_runner.burst()
	_runner.stagger()
	_resolved += 1

	var penalty := STAMINA_WRONG
	if _relic_count("taiwa") > 0:
		penalty *= 0.5
	_stamina = maxf(0.0, _stamina - penalty)

	var retry := _relic_count("minkyo") > 0 or int(SaveGame.get_setting("auto_retry", 0)) == 1
	Srs.record(kana, 0, ms)
	if retry:
		Srs.requeue(kana)
	else:
		_chain = 0

	_od_charge = 0.0
	Sfx.miss()
	_hitstop_until_ms = Time.get_ticks_msec() + 130
	_time_scale_target = 0.30
	_damage_flash = 1.0
	_cam.shake(1.15 * _shake_user, 4.2)
	_cam.punch(-1.1 * _shake_user)
	# 撞錯的那顆石碑已經砸過來了：如果這一撞直接把體力扣到 0，
	# 就不該是「慢慢跪下」，而是被撞飛出去趴在地上。
	if _stamina <= 0.0:
		_begin_collapse(true)
		return

	# 正解只閃在畫面上，不開解說卡。下一題已經在來。
	_hud.hide_explain()
	var choices: Array = _question.get("choices", [])
	var ti := int(_question.get("target_index", 0))
	var shown := str(choices[ti]) if ti >= 0 and ti < choices.size() else ""
	_hud.banner("正解　%s" % shown, Color(1.0, 0.45, 0.42), 0.55)

	_after_resolve(null, 0.40)
	_time_scale_target = 1.0
	_gap = 0.48
	if _hold_miss:
		get_tree().paused = true   # 測試用：停在錯題卡上


func _resolve_dodge(kana: String) -> void:
	_resolved += 1
	_stamina = maxf(0.0, _stamina - STAMINA_DODGE)
	Srs.record(kana, 2, 0.0)
	Srs.requeue(kana)
	_hud.banner("閃避", UiKit.INK_DIM, 0.5)
	_cam.punch(0.6 * _shake_user)
	_after_resolve(null, 0.1)
	_gap = 0.36


## 判定收尾：未命中的石碑淡出、命中的延遲清除
func _after_resolve(hit: Node3D, hit_delay: float) -> void:
	if hit != null:
		_fades.append([hit, hit_delay])
	for i in LANE_COUNT:
		var s: Node3D = _stones[i]
		if s == hit or s.broken:
			continue
		s.fade_out(0.40)
	_duck_timer = 0.0
	_runner.set_duck(false)
	_hud.set_timer(1.0)


func _check_after_gap() -> void:
	if _stamina <= 0.0:
		_begin_collapse()
		return
	if Srs.finished():
		_finish(true)


func _open_relic() -> void:
	state = State.RELIC
	_hud.visible = false          # 選遺物時不要讓 HUD 從底下透出來
	# 三選一 = 時間暫停：路面貼圖、風線、花瓣都要完全停住。
	# get_tree().paused 只停掉 advance()，但路面 shader 的捲動是
	# 由 scroll_speed 參數獨立驅動的，不額外凍結看起來就會像輸送帶。
	_track.set_frozen(true)
	get_tree().paused = true
	_ui.show_relic(_relics)


func _on_relic_chosen(id: String) -> void:
	_relics[id] = _relic_count(id) + 1
	_hud.set_relics(_relics)
	for s in _stones:
		s.always_legible = _relic_count("muga") > 0
	_ui.hide_all()               # 不論從按鈕還是程式觸發都要收掉面板
	_track.set_frozen(false)
	state = State.PLAY
	_hud.visible = true
	get_tree().paused = false
	Engine.time_scale = 1.0
	_time_scale_target = 1.0
	_gap = 0.55


func _relic_count(id: String) -> int:
	return int(_relics.get(id, 0))


# ── 開發用：題目產生器自我檢測 ────────────────────────────────────────────
## 一次生成數千題，驗證「正解一定在選項裡、選項不互撞、
## 混淆題不會出現同音假名當干擾、反向題的羅馬字不重複」等不變量。
func _run_selftest() -> void:
	var checks := 0
	var failures: Array[String] = []
	var by_type := {}
	var target_lane_hist := [0, 0, 0]

	for kind in [KanaDB.Kind.SEION, KanaDB.Kind.DAKUON, KanaDB.Kind.YOON, KanaDB.Kind.KATA]:
		for entry in KanaDB.unit(kind):
			var kana: String = entry[0]
			for step in 40:
				var progress := float(step) / 39.0
				for rep in 6:
					var q := Curriculum.make_question(kana, progress)
					checks += 1
					var type_name: String = Curriculum.QType.keys()[int(q["type"])]
					by_type[type_name] = int(by_type.get(type_name, 0)) + 1

					var choices: Array = q["choices"]
					var sources: Array = q["choice_source"]
					var ti := int(q["target_index"])
					target_lane_hist[ti] += 1

					if choices.size() != LANE_COUNT:
						failures.append("%s: 選項數 %d" % [kana, choices.size()])
					if ti < 0 or ti >= choices.size():
						failures.append("%s: target_index %d 越界" % [kana, ti])
						continue
					if str(sources[ti]) != kana:
						failures.append("%s: target_index 指向的不是正解" % kana)
					for i in choices.size():
						if str(choices[i]) == "":
							failures.append("%s: 有空字串選項" % kana)
						for j in range(i + 1, choices.size()):
							if str(choices[i]) == str(choices[j]):
								failures.append("%s: 選項重複 %s" % [kana, choices[i]])

					# 混淆題不能把同音假名當成干擾，否則玩家答對了卻被判錯
					if int(q["type"]) == Curriculum.QType.ROMAJI:
						for i in choices.size():
							if i == ti:
								continue
							if str(sources[i]) == kana:
								failures.append("%s: 干擾與正解同字" % kana)
							var rr: String = KanaDB.romaji(str(sources[i]))
							if rr == str(q["romaji"]):
								failures.append("%s: 干擾與正解同音（%s）" % [kana, rr])

					# 反向題的羅馬字不可重複
					if int(q["type"]) == Curriculum.QType.KANA_READ:
						var seen := {}
						for c in choices:
							if seen.has(str(c)):
								failures.append("%s: 反向題羅馬字重複 %s" % [kana, c])
							seen[str(c)] = true

					# 挖空題的完整讀音必須真的包含該假名
					if int(q["type"]) == Curriculum.QType.WORD_BLANK:
						if not str(q["word_reading"]).contains(kana):
							failures.append("%s: 詞彙讀音不含目標假名" % kana)
						if not str(q["prompt"]).contains("○"):
							failures.append("%s: 挖空題缺 ○" % kana)

					# 解說卡必須有內容
					var card := Curriculum.explain_card(q)
					if card["kana"] == "" or (card["lines"] as Array).is_empty():
						failures.append("%s: 解說卡是空的" % kana)

	print("[selftest] generated %d questions" % checks)
	print("[selftest] by type: %s" % str(by_type))
	print("[selftest] target lane spread: %s" % str(target_lane_hist))
	if failures.is_empty():
		print("[selftest] PASS — all invariants hold")
	else:
		var uniq := {}
		for f in failures:
			uniq[f] = int(uniq.get(f, 0)) + 1
		print("[selftest] FAIL — %d issues (%d distinct):" % [failures.size(), uniq.size()])
		for k in uniq.keys():
			print("[selftest]   x%d  %s" % [uniq[k], k])
	get_tree().quit(0 if failures.is_empty() else 1)


func _autopilot() -> void:
	if not _wave_active:
		return
	# 障礙波沒有題目：最佳解是換到綠色空道站著通過，不該靠蹲（蹲要扣體力）
	if _obstacle_wave:
		if _lane != 0 and not _barrier.blocks(_lane):
			return
		for i in LANE_COUNT:
			if not _barrier.blocks(i):
				_go_lane(i)
				return
		return
	var target := int(_question["target_index"])
	# 練到一半會偶爾失手：每 7 題故意撞錯一次（--perfect 可關閉）
	var sabotage := _always_miss or (_autoplay_sabotage and (_resolved / 7) % 2 == 1 and _chain >= 3)
	if _wave_z > -8.0:
		_go_lane(target if not sabotage else (target + 1) % LANE_COUNT)
	elif _lane != target:
		_go_lane(target)


# ── 開發用：三根石碑必須同時可見 ────────────────────────────────────────
## 石碑是同一個物件池（3 個）重複使用的，任何「只剩兩根」都是 bug。
## 這段會在推動到玩家面前之後檢查可見性與縮放，把第一次違規的上下文印出來。
var _watch_violations := 0
var _watch_printed := 0
var _hitstop_frames := 0
var _max_hitstop_frames := 0
var _watch_run := 0
var _watch_longest := 0


func _watch_stones(_delta: float) -> void:
	if not _watch:
		return
	if _hitstop_until_ms > Time.get_ticks_msec():
		_hitstop_frames += 1
		_max_hitstop_frames = maxi(_max_hitstop_frames, _hitstop_frames)
	else:
		_hitstop_frames = 0

	if state != State.PLAY or not _wave_active or _wave_z < -34.0:
		return
	# 障礙波本來就沒有石碑（畫面上只有一條橫桿），
	# 不排除的話每局插入的九次障礙都會被誤報成「石碑消失」。
	if _obstacle_wave:
		return
	var hidden: Array = []
	for i in LANE_COUNT:
		var s: Node3D = _stones[i]
		# 只檢查「看不見」。縮放中（剛生成）不算，那是正常的出現動畫。
		if not s.visible:
			hidden.append(i)
	if not hidden.is_empty():
		_watch_violations += 1
		_watch_run += 1
		if _watch_run > _watch_longest:
			_watch_longest = _watch_run
		if _watch_printed < 3:
			_watch_printed += 1
			var tags: Array = []
			for i2 in LANE_COUNT:
				var st: Node3D = _stones[i2]
				if not st.visible:
					tags.append("%d:%s fading=%.2f/%.2f" % [
						i2, st.dbg_tag, st._fade_t, st._fade_dur])
			print("[watch] frame=%d missing=%s wave_z=%.1f gap=%.2f run=%d fades=%s resolved=%d" % [
				_frames, str(tags), _wave_z, _gap, _watch_run,
				str(_fades.size()), _resolved])
	else:
		if _watch_run > 1:
			print("[watch]   -> 這次連續缺失 %d 幀" % _watch_run)
		_watch_run = 0



func _capture_and_quit() -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := _shot_path
	if path == "":
		path = "user://shot_%d.png" % _shot_frame
	var err := img.save_png(path)
	print("[kana-run] screenshot -> %s (%s)" % [path, "ok" if err == OK else "FAILED"])
	_dump_probe(img)
	get_tree().quit()


## 開發用：把關鍵材質的實際參數與畫面取樣印出來，
## 避免「靠猜調參數」。正式版不會用到。
func _dump_probe(img: Image) -> void:
	var w := img.get_width()
	var h := img.get_height()
	# 取幾個有代表性的螢幕位置
	var spots := {
		"石身正面": Vector2i(int(w * 0.50), int(h * 0.52)),
		"石身頂面": Vector2i(int(w * 0.50), int(h * 0.40)),
		"路面中央": Vector2i(int(w * 0.50), int(h * 0.80)),
		"天空": Vector2i(int(w * 0.08), int(h * 0.12)),
	}
	for key in spots.keys():
		var c := img.get_pixelv(spots[key])
		print("[probe] %s %s" % [key, c.to_html(false)])
	if not _question.is_empty():
		print("[probe] question type=%s prompt=%s choices=%s target=%d" % [
			str(Curriculum.QType.keys()[int(_question.get("type", 0))]),
			str(_question.get("prompt", "")),
			str(_question.get("choices", [])),
			int(_question.get("target_index", -1))])

	if not _stones.is_empty():
		var mat: ShaderMaterial = _stones[0].get_child(1).material_override as ShaderMaterial
		if mat != null:
			print("[probe] stone base_color=%s rim_gain=%s highlight=%s" % [
				str(mat.get_shader_parameter("base_color")),
				str(mat.get_shader_parameter("rim_gain")),
				str(mat.get_shader_parameter("highlight"))])


# ── 詞彙寶石 ────────────────────────────────────────────────────────────
func _maybe_spawn_gem() -> void:
	_gem_active = false
	_gem.visible = false
	if _relic_count("sesshu") == 0 or randf() > 0.55:
		return
	_gem_word = RelicPool.gem_word(RandomNumberGenerator.new())
	if _gem_word.is_empty():
		return
	_gem_lane = randi() % LANE_COUNT
	_gem_z = SPAWN_Z * 0.9
	_gem_t = 0.0
	_gem_active = true
	_gem.visible = true
	_gem.position = Vector3(LANE_X[_gem_lane], 1.1, _gem_z)
	_gem_label.text = str(_gem_word[0])


func _advance_gem(dt: float) -> void:
	if not _gem_active:
		return
	_gem_t += dt
	_gem_z += _speed * dt
	_gem.position = Vector3(LANE_X[_gem_lane], 1.1 + sin(_gem_t * 3.0) * 0.14, _gem_z)
	_gem.rotation.y += dt * 2.2
	_gem_core.rotation.y += dt * 1.6
	if _gem_z >= 0.0:
		_gem_active = false
		_gem.visible = false
		if _gem_lane == _lane:
			if SaveGame.collect_word("%s %s" % [_gem_word[0], _gem_word[1]]):
				Sfx.word_collect()
				_gem_count += 1
				_hud.banner(str(_gem_word[0]), Color(0.55, 0.95, 0.85), 0.7)


# ── 結算 ────────────────────────────────────────────────────────────────
func _finish(cleared: bool) -> void:
	if state == State.RESULTS or state == State.TITLE:
		return
	state = State.RESULTS
	get_tree().paused = false
	Engine.time_scale = 1.0
	_time_scale_target = 1.0
	_hud.visible = false
	_hud.hide_explain()
	for s in _stones:
		s.clear()
	_fades.clear()
	_gem.visible = false
	_gem_active = false

	var unit_key: String = str(unit_kinds[0]) if unit_kinds.size() == 1 else "all"
	if cleared:
		SaveGame.set_best_score(unit_key, _score)
		Sfx.fanfare()
	SaveGame.flush()

	_ui.show_results({
		"cleared": cleared,
		"score": _score,
		"correct": Srs.session_correct,
		"wrong": Srs.session_wrong,
		"dodged": Srs.session_dodged,
		"answered": Srs.answered_this_run(),
		"best_combo": _best_chain,
		"weakest": Srs.weakest(10),
		"slowest": Srs.slowest(4),
	})
