extends Node3D
## Monolith — 一顆刻著假名的石碑。
##
## 造型：底座 + 碑身 + 頂蓋。碑身由 3×4 的碎石塊組成，
## 平常密合成整顆石頭，撞對時才真的「碎開」—— 每一塊帶著自己的
## 速度與角速度飛出去。這比「噴一堆粒子」有重量感得多。
##
## 外觀靠倒角稜線挑出的輪廓光，碑面假名以 3D 標籤鑲嵌，
## 靠自發光與描邊在高速下維持可讀性。

const WIDTH := 1.62
const HEIGHT := 4.05
const DEPTH := 0.50
const SPAWN_Z := -50.0
const IMPACT_Z := 0.0

const COLS := 3
const ROWS := 4
const GRAVITY := -26.0
const SHATTER_LIFE := 1.05   ## 碎石塊存在的秒數
const CRUSH_LIFE := 0.85     ## 撲向鏡頭的時間

var kana := ""
var is_answer := false
var broken := false
var always_legible := false      ## 心眼：無視距離
var show_hint := false           ## 透視：接近時顯示羅馬字

## 開發用：記錄是誰把這顆石碑清掉的
var dbg_tag := ""

var _body: Node3D                ## 所有外觀都在這底下，方便整體縮放
var _shell: MeshInstance3D      ## 完整的外殼；碎裂前一直是它
var _pieces: Array[Node3D] = []  ## 預先藏在殼內的碎石塊
var _cap_piece: Node3D
var _chunk_mesh: ArrayMesh
var _cap_mesh: ArrayMesh
var _label: Label3D
var _hint: Label3D
var _halo: MeshInstance3D
var _halo_mat: StandardMaterial3D
var _aura: MeshInstance3D
var _aura_mat: StandardMaterial3D
var _shock: MeshInstance3D
var _shock_mat: StandardMaterial3D
var _runes: Array[MeshInstance3D] = []
var _mat: ShaderMaterial
var _debris: CPUParticles3D

var _spawn := 0.0
var _fading := false
var _fade_t := 0.0
var _fade_dur := 0.35
var _pulse := 0.0
var _highlight := 0.0
var _shock_t := 0.0
var _halo_t := 0.0
var _speed_hint := 0.0

# 碎石物理
var _shattered := false
var _shove := 0.0             ## 撞錯時「撲向鏡頭」的進度
var _shove_from := 0.0
var _pieces_visible := false
var _shatter_t := 0.0
var _p_vel: Array[Vector3] = []
var _p_spin: Array[Vector3] = []
var _p_home: Array[Vector3] = []


func _ready() -> void:
	_build()


func _build() -> void:
	_mat = SceneKit.stone_material().duplicate() as ShaderMaterial

	_body = Node3D.new()
	add_child(_body)

	# ── 底座 ──
	_body.add_child(_make_box(Vector3(WIDTH + 0.5, 0.34, DEPTH + 0.34), 0.07, Vector3(0, 0.17, 0)))

	# ── 碑身：完整外殼 ──
	# 完整狀態只顯示這一個實心倒角箱，所以輪廓乾淨；
	# 下面 12 塊碎石預先藏在殼裡面，撞對時外殼消失才露出來。
	_shell = _make_box(Vector3(WIDTH, HEIGHT, DEPTH), 0.07,
		Vector3(0, 0.34 + HEIGHT * 0.5, 0))
	_body.add_child(_shell)

	# ── 碑身：預先碎塊（藏在外殼內） ──
	var cw := WIDTH / float(COLS)
	var ch := HEIGHT / float(ROWS)
	# 每塊比它的格子小一圈，碎開時才看得出斷裂縫
	_chunk_mesh = SceneKit.chamfer_box(Vector3(cw - 0.10, ch - 0.10, DEPTH - 0.07), 0.028)
	for cx in COLS:
		for ry in ROWS:
			var home := Vector3(
				-WIDTH * 0.5 + cw * (float(cx) + 0.5),
				0.34 + ch * (float(ry) + 0.5),
				0.0)
			_pieces.append(_add_piece(_chunk_mesh, home))

	# ── 頂蓋（也是一塊，撞破時整片飛走） ──
	_cap_mesh = SceneKit.chamfer_box(Vector3(WIDTH + 0.28, 0.22, DEPTH + 0.26), 0.06)
	_cap_piece = _add_piece(_cap_mesh, Vector3(0, 0.34 + HEIGHT + 0.10, 0))
	_pieces.append(_cap_piece)

	# ── 側邊刻紋 ──
	for side in [-1, 1]:
		for i in 3:
			var r := MeshInstance3D.new()
			r.mesh = SceneKit.chamfer_box(Vector3(0.07, 1.5 - i * 0.3, 0.07), 0.02)
			r.material_override = SceneKit.glow_material(Color(0.42, 0.52, 0.9), 0.9)
			r.position = Vector3(side * (WIDTH * 0.5 - 0.10), 1.1 + i * 0.85, DEPTH * 0.5 + 0.02)
			_body.add_child(r)
			_runes.append(r)

	_label = SceneKit.make_kana_label()
	_label.position = Vector3(0, 0.34 + HEIGHT * 0.55, DEPTH * 0.5 + 0.035)
	_body.add_child(_label)

	_hint = SceneKit.make_romaji_label()
	_hint.font = FontKit.bold
	_hint.font_size = 44
	_hint.pixel_size = 0.010
	_hint.modulate = Color(0.70, 0.88, 1.0)
	_hint.position = Vector3(0, 0.34 + 0.70, DEPTH * 0.5 + 0.04)
	_hint.visible = false
	_body.add_child(_hint)

	_halo_mat = SceneKit.glow_material(Color(1.0, 0.92, 0.70), 4.0).duplicate() as StandardMaterial3D
	_halo = MeshInstance3D.new()
	var ring := PlaneMesh.new()
	ring.size = Vector2(6.0, 6.0)
	_halo.mesh = ring
	_halo.material_override = _halo_mat
	_halo.position = Vector3(0, 2.1, 1.05)
	_halo.visible = false
	add_child(_halo)

	# 心眼專用：石碑背後的青色光暈。
	# 遠處的碑面本來就會隨距離變暗，拿到心眼之後加這圈光，
	# 遠方的三顆石碑會整個亮起來 —— 玩家一眼就看得出「我現在看得比別人遠」。
	var aura_mat := SceneKit.glow_material(Color(0.45, 0.85, 1.0), 1.15).duplicate() as StandardMaterial3D
	_aura_mat = aura_mat
	_aura = MeshInstance3D.new()
	var aura_plane := PlaneMesh.new()
	aura_plane.size = Vector2(4.4, 7.0)
	_aura.mesh = aura_plane
	_aura.material_override = aura_mat
	_aura.position = Vector3(0, 2.2, -0.55)
	_aura.visible = false
	add_child(_aura)

	_shock_mat = SceneKit.glow_material(Color(1.0, 0.95, 0.80), 4.0).duplicate() as StandardMaterial3D
	_shock = MeshInstance3D.new()
	var sp := PlaneMesh.new()
	sp.size = Vector2.ONE
	_shock.mesh = sp
	_shock.material_override = _shock_mat
	_shock.position = Vector3(0, 2.1, 0.7)
	_shock.visible = false
	add_child(_shock)

	# 細碎粉末
	_debris = CPUParticles3D.new()
	_debris.emitting = false
	_debris.one_shot = true
	_debris.explosiveness = 0.95
	_debris.amount = 30
	_debris.lifetime = 0.9
	_debris.direction = Vector3(0, 0.4, 1)
	_debris.spread = 68.0
	_debris.initial_velocity_min = 4.0
	_debris.initial_velocity_max = 14.0
	_debris.gravity = Vector3(0, -22.0, 0)
	_debris.damping_min = 0.4
	_debris.damping_max = 1.2
	_debris.angular_velocity_min = -540.0
	_debris.angular_velocity_max = 540.0
	_debris.scale_amount_min = 0.12
	_debris.scale_amount_max = 0.36
	var chip := SceneKit.blob(0.30, 4, 6).duplicate() as SphereMesh
	chip.surface_set_material(0, SceneKit.toon_material(Color(0.30, 0.29, 0.38), 0.7, 0.8, 0.10))
	_debris.mesh = chip
	_debris.position = Vector3(0, 2.1, 0.3)
	add_child(_debris)

	visible = false


func _make_box(size: Vector3, chamfer: float, pos: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = SceneKit.chamfer_box(size, chamfer)
	mi.material_override = _mat
	mi.position = pos
	return mi


## 追加一塊碎石到物理陣列
func _add_piece(mesh: ArrayMesh, home: Vector3) -> Node3D:
	var piece := Node3D.new()
	piece.position = home
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = _mat
	piece.add_child(mi)
	piece.visible = false
	_body.add_child(piece)
	_p_home.append(home)
	_p_vel.append(Vector3.ZERO)
	_p_spin.append(Vector3.ZERO)
	return piece


# ── 設定 ────────────────────────────────────────────────────────────────
## is_kana=false 時碑面改用拉丁字型與較小的字級（反向題的羅馬字選項）
func setup(text: String, answer: bool, is_kana := true, hint_text := "") -> void:
	kana = text
	is_answer = answer
	broken = false
	visible = true
	_spawn = 0.0
	_fading = false
	_fade_t = 0.0
	_shattered = false
	_shove = 0.0
	_legible_elapsed = 0.0
	_window_fading = false
	_pieces_visible = false
	_shatter_t = 0.0
	_highlight = 0.0
	_shock_t = 0.0
	_halo_t = 0.0
	_pulse = randf() * TAU
	position = Vector3(position.x, 0, SPAWN_Z)
	rotation = Vector3.ZERO
	_body.scale = Vector3(0.02, 0.02, 0.02)
	_body.position = Vector3.ZERO
	_body.rotation = Vector3.ZERO

	# 把碎石塊收回組裝位置並藏起來，只留完整外殼
	_shell.visible = true
	for i in _pieces.size():
		_pieces[i].position = _p_home[i]
		_pieces[i].rotation = Vector3.ZERO
		_pieces[i].scale = Vector3.ONE
		_pieces[i].visible = false
		_p_vel[i] = Vector3.ZERO
		_p_spin[i] = Vector3.ZERO

	if is_kana:
		_label.text = text
		_label.font = FontKit.display
		_label.font_size = 150 if text.length() == 1 else 106
		_label.pixel_size = 0.0105 if text.length() == 1 else 0.0128
		_label.modulate = SceneKit.COL_INLAY
	else:
		_label.text = text
		_label.font = FontKit.bold
		_label.font_size = 96
		_label.pixel_size = 0.0135
		_label.modulate = Color(0.78, 0.92, 1.0)
	_label.outline_size = 7
	_label.modulate.a = 1.0
	_label.visible = true
	_hint.text = hint_text
	_hint.visible = hint_text != "" and show_hint
	for r in _runes:
		r.visible = true
	_shell.visible = true
	for p in _pieces:
		p.visible = false
	_halo.visible = false
	_shock.visible = false
	_aura.visible = always_legible
	_debris.emitting = false
	_mat.set_shader_parameter("highlight", 0.0)


func clear() -> void:
	visible = false
	_hint.visible = false
	_debris.emitting = false
	_shattered = false
	_shove = 0.0
	_pieces_visible = false
	_shell.visible = true
	for p in _pieces:
		p.visible = false
	_body.position = Vector3.ZERO
	_body.rotation = Vector3.ZERO


## 碎石塊是否還在空中
func shattering() -> bool:
	return _shattered


func set_speed_hint(v: float) -> void:
	_speed_hint = v


## 極限模式：碑面在「可讀窗口」結束後迅速淡出。
##
## 為什麼要這樣而不是單純加速：加速會讓「看清」變得更難，
## 但那是同一種難度曲線的延伸，玩家只會覺得題目變了。
## 讓碑面「一閃就滅」是另一種東西 —— 逼你在半懂不懂的時候就必須出手，
## 逼迫感來自「不確定」而不是「來不及」。
var _legible_window := 1.0
var _legible_elapsed := 0.0
var _window_fading := false

func set_legible_window(scale01: float) -> void:
	_legible_window = clampf(scale01, 0.1, 1.0)


# ── 撞破 ────────────────────────────────────────────────────────────────
## 真正的碎裂：每一塊從撞擊點獲得衝量，往鏡頭方向飛並翻滾。
func smash(impact_x := 0.0) -> void:
	if broken:
		return
	broken = true
	_shattered = true
	_shatter_t = 0.0

	# 整顆外殼瞬間消失，換成 13 塊帶縫隙的碎石
	_shell.visible = false

	_debris.restart()
	_debris.emitting = true
	_shock.visible = true
	_shock_t = 0.0
	_halo.visible = true
	_halo_t = 0.0
	_hint.visible = false
	_highlight = 0.55
	_launch_pieces(false)


## 讓每一塊碎石飛出去。toward=true 是撞錯（整片撲向鏡頭），
## false 是答對（往側邊散開，不擋住跑者）。
func _launch_pieces(toward: bool) -> void:
	_pieces_visible = true
	var impact := Vector3(_shove_from, 0.34 + HEIGHT * 0.5, DEPTH * 0.5)
	if not toward:
		impact.x = 0.0
	for i in _pieces.size():
		var piece := _pieces[i]
		var offset := _p_home[i] - impact
		# 越靠近撞擊點 → 飛得越快越遠
		var dist := maxf(0.35, offset.length())
		var dir: Vector3
		var power: float
		if toward:
			dir = (offset.normalized() * 0.55 + Vector3(0, 0.1, 1.0)).normalized()
			power = clampf(13.0 / dist, 4.0, 11.0)
			_p_vel[i] = dir * power + Vector3(
				randf_range(-1.2, 1.2), randf_range(-0.5, 1.8), randf_range(1.0, 3.0))
		else:
			# 偏側向散開，不要整片朝鏡頭撲過來擋住跑者
			dir = (offset.normalized() * 1.35 + Vector3(0, 0, 0.15)).normalized()
			power = clampf(11.0 / dist, 3.0, 9.0)
			_p_vel[i] = dir * power + Vector3(
				randf_range(-1.0, 1.0), randf_range(0.2, 2.4), randf_range(0.4, 2.2))
		_p_spin[i] = Vector3(
			randf_range(-9.0, 9.0), randf_range(-9.0, 9.0), randf_range(-9.0, 9.0))
		piece.visible = true


func reject() -> void:
	_hint.visible = false
	_highlight = 0.0


## 答錯時撞過來：整顆石碑向鏡頭撲過來再碎開。
## 和 smash() 的差別是方向與份量 —— 錯的那顆是「砸到你」，不是「被你撞破」。
func crush(from_x := 0.0) -> void:
	if broken:
		return
	broken = true
	_shattered = true
	_shatter_t = 0.0
	_shell.visible = false

	_debris.restart()
	_debris.emitting = true
	_hint.visible = false
	_highlight = 0.20
	_label.modulate = Color(1.0, 0.45, 0.45)

	# 先整顆往鏡頭猛撲，再在近距離炸開
	_shove = 1.0
	_shove_from = from_x
	_pieces_visible = false

## 判定後未命中的石碑：下陷並淡出
func fade_out(duration := 0.35) -> void:
	_fading = true
	_fade_t = 0.0
	_fade_dur = maxf(0.05, duration)


# ── 每幀 ────────────────────────────────────────────────────────────────
func _process(delta: float) -> void:
	if not visible:
		return

	if _shattered:
		_process_shatter(delta)
		return

	if _fading:
		_fade_t += delta
		var k := clampf(_fade_t / _fade_dur, 0.0, 1.0)
		_body.scale = Vector3.ONE * Vector3(lerpf(1.0, 0.55, k), lerpf(1.0, 0.15, k), 1.0)
		_body.position.y = -1.4 * k * k
		_label.modulate.a = 1.0 - k
		if k >= 1.0:
			dbg_tag = "fade_out_done"
			clear()
		return

	# 出現：由小放大，帶一點過衝
	if _spawn < 1.0:
		_spawn = minf(1.0, _spawn + delta * 5.5)
		var e := 1.0 - pow(1.0 - _spawn, 3.0)
		var overshoot := 1.0 + sin(_spawn * PI) * 0.08
		_body.scale = Vector3.ONE * e * overshoot

	# 呼吸脈動：遠處也能注意到碑面
	_pulse += delta * (2.0 + _speed_hint * 2.5)
	var glow := 0.5 + 0.5 * sin(_pulse)
	_label.outline_size = int(lerpf(5.0, 10.0, glow))
	_label.modulate = _label.modulate.lerp(Color(1, 1, 1), glow * 0.20)

	# 極限：碑面快速閃爍而不是直接淡出。
	#
	# 為什麼是「閃」不是「淡」：淡出到看不見等於把題目拿掉，
	# 玩家會覺得自己被剝奪了作答機會，那是在懲罰他。
	# 明滅則是「還在這裡，但你要更快」——
	# 讀到的機會還在，只是要靠記憶補上，賭博的感覺完全不同。
	#
	# 滅到 0.42 而不是 0：全黑的那一格在截圖裡會整顆消失，
	# 而極限的 0.176 秒週期遠小於一題從進場到判定的時間，
	# 單張截圖抓到全黑不代表玩家看得到全黑。
	if _legible_window < 1.0:
		_legible_elapsed += delta
		var period := maxf(0.32 * _legible_window, 0.16)
		var ph := fmod(_legible_elapsed, period) / period
		var flick := 1.0 if ph < 0.55 else lerpf(0.42, 0.85, (ph - 0.55) / 0.45)
		_label.modulate.a = flick
		if _hint.visible:
			_hint.modulate.a = flick
		_mat.set_shader_parameter("highlight", flick * 0.5)

	# 距離越遠碑面越暗（除非持有心眼）
	if not always_legible:
		var far := clampf((-position.z - 26.0) / 34.0, 0.0, 1.0)
		_label.modulate = _label.modulate.lerp(Color(0.62, 0.60, 0.66), far * 0.55)
	else:
		# 心眼：光暈呼吸，且越遠越亮，讓遠方石碑主跳出來
		_aura.visible = true
		var breathe := 0.55 + 0.45 * sin(_pulse * 0.7)
		var far := clampf((-position.z - 20.0) / 40.0, 0.0, 1.0)
		_aura_mat.emission_energy_multiplier = (0.5 + 1.5 * far) * (0.75 + 0.35 * breathe)
	if show_hint and position.z > -24.0:
		_hint.visible = true

	_highlight = maxf(0.0, _highlight - delta * 2.2)
	_mat.set_shader_parameter("highlight", _highlight)

	if _shock.visible:
		_shock_t += delta * 2.4
		_shock.scale = Vector3.ONE * (0.6 + _shock_t * 7.0)
		_shock_mat.emission_energy_multiplier = maxf(0.0, 4.0 * (1.0 - _shock_t))
		if _shock_t >= 1.0:
			_shock.visible = false

	if _halo.visible:
		_halo_t += delta * 2.0
		_halo.scale = Vector3.ONE * (0.5 + _halo_t * 1.4)
		_halo_mat.emission_energy_multiplier = maxf(0.0, 4.0 * (1.0 - _halo_t))
		if _halo_t >= 1.0:
			_halo.visible = false


func _process_shatter(delta: float) -> void:
	_shatter_t += delta

	# 撞錯：整顆先撲向鏡頭，到近距離才炸開
	if _shove > 0.0:
		_shove = maxf(0.0, _shove - delta / 0.13)
		var e := 1.0 - pow(_shove, 2.4)
		_body.position.z = e * 4.6
		_body.position.x = (_shove_from - _body.position.x) * e * 0.35
		_body.rotation.x = -e * 0.42
		_body.scale = Vector3.ONE * (1.0 + e * 0.55)
		if _shove <= 0.0 and not _pieces_visible:
			_body.position = Vector3.ZERO
			_body.rotation = Vector3.ZERO
			_body.scale = Vector3.ONE
			_pieces_visible = true
			_launch_pieces(true)

	# 尾巴 0.35 秒把碎塊縮掉，避免整片殘骸一直擋在跑者前面
	var shrink := clampf(1.0 - (_shatter_t - (SHATTER_LIFE - 0.35)) / 0.35, 0.0, 1.0)
	var s := 0.12 + 0.88 * shrink

	for i in _pieces.size():
		var piece := _pieces[i]
		if _pieces_visible:
			var v: Vector3 = _p_vel[i]
			v.y += GRAVITY * delta
			_p_vel[i] = v
			piece.position += v * delta
			piece.rotation += _p_spin[i] * delta
			piece.scale = Vector3.ONE * s
			# 落地反彈一下就滑走
			if piece.position.y < 0.10 and v.y < 0.0:
				piece.position.y = 0.10
				_p_vel[i] = Vector3(v.x * 0.55, -v.y * 0.22, v.z * 0.55)
				_p_spin[i] = _p_spin[i] * 0.5

	# 假名與刻紋快速淡出（石塊已經飛開了）
	var f := clampf(1.0 - _shatter_t / 0.22, 0.0, 1.0)
	_label.modulate.a = f
	for r in _runes:
		var m := r.material_override as StandardMaterial3D
		if m != null and m.emission_enabled:
			m.emission_energy_multiplier = 0.9 * f

	if _shatter_t >= SHATTER_LIFE:
		dbg_tag = "shatter_done"
		clear()
		return

	if _shock.visible:
		_shock_t += delta * 2.4
		_shock.scale = Vector3.ONE * (0.6 + _shock_t * 7.0)
		_shock_mat.emission_energy_multiplier = maxf(0.0, 4.0 * (1.0 - _shock_t))
		if _shock_t >= 1.0:
			_shock.visible = false

	if _halo.visible:
		_halo_t += delta * 2.0
		_halo.scale = Vector3.ONE * (0.5 + _halo_t * 1.4)
		_halo_mat.emission_energy_multiplier = maxf(0.0, 4.0 * (1.0 - _halo_t))
		if _halo_t >= 1.0:
			_halo.visible = false

	_highlight = maxf(0.0, _highlight - delta * 1.4)
	_mat.set_shader_parameter("highlight", _highlight)
