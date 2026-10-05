extends Node3D
## Track — 場景本體：路面、燈籠、鳥居、地面裝飾、風切線、漂浮粒子。
##
## 採「世界往鏡頭移動」的做法，跑者固定在 z=0。
## 好處是長跑也不會有浮點精度問題，所有物件只需在通過後回收重生。

const ROAD_WIDTH := 10.0
const ROAD_LENGTH := 240.0
const ROAD_START := 24.0          # 跑者身後
const ROAD_END := -216.0

const LANE_X := 2.7               # 三條跑道的中心間距的一半
const DASH_SPAN := 7.5
const DASH_COUNT := 20
const LANTERN_SPAN := 16.0
const LANTERN_COUNT := 8
const GATE_SPAN := 46.0
const GATE_COUNT := 5
const SPEEDLINE_COUNT := 90
const RECYCLE_Z := 26.0

var theme := 0
var env: Environment
var speed01 := 0.0
var _frozen := false
var _weather_kind := ""
var _weather_gravity := Vector3.ZERO
var _weather_tint := Color.WHITE
var _dashes: Array[Node3D] = []
var _lanterns: Array[Node3D] = []
var _gates: Array[Node3D] = []
var _shoulder_l: Array[Node3D] = []
var _shoulder_r: Array[Node3D] = []
var _speed_lines: MultiMeshInstance3D
var _petals: CPUParticles3D
var _road_mat: ShaderMaterial
var _ridges: Array[MeshInstance3D] = []
var _ridge_mats: Array[StandardMaterial3D] = []
var _zone := 0
var _travel := 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.seed = 4711
	_build_sky()
	_build_ground()
	_build_road()
	_build_dashes()
	_build_lanterns()
	_build_gates()
	_build_shrine()
	_build_shoulders()
	_build_speed_lines()
	_build_ambient()


# ── 天空與遠景 ──────────────────────────────────────────────────────────
func _build_sky() -> void:
	var holder := WorldEnvironment.new()
	env = SceneKit.build_environment(_quality())
	holder.environment = env
	add_child(holder)

	var stars := SceneKit.make_star_field(420, 900.0)
	add_child(stars)
	add_child(SceneKit.make_moon())

	# 三層：遠山帶一點自發光（空氣透視），中景接色，近山壓暗但仍吃側光。
	_add_ridge(520.0, 120.0, 96, 991, 0.5, -6.0, Color(0.48, 0.52, 0.72), 0.32)
	_add_ridge(400.0, 86.0, 84, 1501, 0.55, -5.0, Color(0.28, 0.26, 0.42), 0.14)
	_add_ridge(300.0, 62.0, 72, 1777, 0.7, -4.0, Color(0.16, 0.13, 0.22), 0.06)
	_paint_ridges(0)


func _quality() -> int:
	return int(SaveGame.get_setting("quality", 1))


func _add_ridge(radius: float, height: float, segments: int, seed: int, jag: float, y: float, color: Color, emission: float) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = SceneKit.mountain_ring(radius, height, segments, seed, jag)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.92
	mat.metallic = 0.0
	if emission > 0.0:
		mat.emission_enabled = true
		mat.emission = color
		mat.emission_energy_multiplier = emission
	mi.material_override = mat
	mi.position.y = y
	add_child(mi)
	_ridges.append(mi)
	_ridge_mats.append(mat)


func _paint_ridges(zone: int) -> void:
	var palettes := [
		[Color(0.48, 0.52, 0.72), Color(0.28, 0.26, 0.42), Color(0.16, 0.13, 0.22)],
		[Color(0.40, 0.50, 0.68), Color(0.22, 0.28, 0.42), Color(0.13, 0.16, 0.26)],
		[Color(0.58, 0.38, 0.50), Color(0.36, 0.20, 0.30), Color(0.20, 0.11, 0.16)],
		[Color(0.50, 0.26, 0.32), Color(0.30, 0.14, 0.18), Color(0.16, 0.08, 0.11)],
	]
	var colors: Array = palettes[clampi(zone, 0, palettes.size() - 1)]
	for i in _ridge_mats.size():
		var mat := _ridge_mats[i]
		var col: Color = colors[mini(i, colors.size() - 1)]
		mat.albedo_color = col
		if mat.emission_enabled:
			mat.emission = col


# ── 地面 ────────────────────────────────────────────────────────────────
func _build_ground() -> void:
	var plane := PlaneMesh.new()
	plane.size = Vector2(420, 520)
	plane.subdivide_width = 1
	plane.subdivide_depth = 1
	var mi := MeshInstance3D.new()
	mi.mesh = plane
	mi.position = Vector3(0, -0.06, -180)
	var mat := SceneKit.flat_material(Color(0.055, 0.046, 0.078))
	mat.roughness = 1.0
	mi.material_override = mat
	add_child(mi)

	# 路肩石階：兩側略高的平台，讓路面有「被挖出來」的層次
	for side in [-1, 1]:
		var step := MeshInstance3D.new()
		var box := SceneKit.chamfer_box(Vector3(5.0, 0.5, ROAD_LENGTH), 0.08)
		step.mesh = box
		step.position = Vector3(side * (ROAD_WIDTH * 0.5 + 2.4), 0.16, -100)
		step.material_override = SceneKit.flat_material(Color(0.10, 0.082, 0.13))
		add_child(step)


func _build_road() -> void:
	var plane := PlaneMesh.new()
	plane.size = Vector2(ROAD_WIDTH, ROAD_LENGTH)
	var mi := MeshInstance3D.new()
	mi.mesh = plane
	mi.position = Vector3(0, 0.0, ROAD_START - ROAD_LENGTH * 0.5)
	_road_mat = SceneKit.road_material()
	_road_mat.set_shader_parameter("road_length", ROAD_LENGTH)
	_road_mat.set_shader_parameter("travel", 0.0)
	mi.material_override = _road_mat
	add_child(mi)


# ── 跑道虛線 ────────────────────────────────────────────────────────────
func _build_dashes() -> void:
	var plane := PlaneMesh.new()
	plane.size = Vector2(0.30, 4.6)
	var mat := SceneKit.glow_material(Color(0.78, 0.86, 1.0), 3.6)
	for row in [-1, 1]:
		for i in DASH_COUNT:
			var mi := MeshInstance3D.new()
			mi.mesh = plane
			mi.material_override = mat
			mi.position = Vector3(row * LANE_X * 0.5, 0.02, 0)
			add_child(mi)
			_dashes.append(mi)
	# 起跑線
	var start := MeshInstance3D.new()
	var sp := PlaneMesh.new()
	sp.size = Vector2(ROAD_WIDTH, 0.9)
	start.mesh = sp
	start.material_override = SceneKit.glow_material(Color(1.0, 0.72, 0.45), 2.8)
	start.position = Vector3(0, 0.02, 6.2)
	add_child(start)


# ── 燈籠 ────────────────────────────────────────────────────────────────
func _build_lanterns() -> void:
	for side in [-1, 1]:
		for i in LANTERN_COUNT:
			var l := SceneKit.make_lantern()
			l.position = Vector3(side * (ROAD_WIDTH * 0.5 + 1.3), 0.35, 0)
			if side > 0:
				l.rotation.y = PI
			add_child(l)
			_lanterns.append(l)


# ── 鳥居：穿過的瞬間是全遊戲最有記憶點的一刻 ─────────────────────────────
func _build_gates() -> void:
	for i in GATE_COUNT:
		var g := _make_gate()
		add_child(g)
		_gates.append(g)


func _make_gate() -> Node3D:
	var root := Node3D.new()
	var wood := SceneKit.flat_material(Color(0.86, 0.16, 0.11))
	var wood_dark := SceneKit.flat_material(Color(0.48, 0.07, 0.06))
	var edge := SceneKit.glow_material(Color(1.0, 0.62, 0.28), 1.4)

	var half := ROAD_WIDTH * 0.5 + 0.85
	var post_h := 7.2
	for side in [-1, 1]:
		var post := MeshInstance3D.new()
		post.mesh = SceneKit.chamfer_box(Vector3(0.58, post_h, 0.58), 0.07)
		post.material_override = wood
		post.position = Vector3(side * half, post_h * 0.5, 0)
		root.add_child(post)

		var foot := MeshInstance3D.new()
		foot.mesh = SceneKit.chamfer_box(Vector3(1.05, 0.42, 1.05), 0.06)
		foot.material_override = wood_dark
		foot.position = Vector3(side * half, 0.21, 0)
		root.add_child(foot)

	# 上橫樑（帶兩端上揚的造型）
	var beam := MeshInstance3D.new()
	beam.mesh = SceneKit.chamfer_box(Vector3(half * 2.0 + 2.8, 0.58, 0.82), 0.09)
	beam.material_override = wood
	beam.position = Vector3(0, post_h - 0.32, 0)
	root.add_child(beam)

	var beam2 := MeshInstance3D.new()
	beam2.mesh = SceneKit.chamfer_box(Vector3(half * 2.0 + 1.6, 0.34, 0.58), 0.06)
	beam2.material_override = wood_dark
	beam2.position = Vector3(0, post_h - 1.25, 0)
	root.add_child(beam2)

	var glow := MeshInstance3D.new()
	var gp := PlaneMesh.new()
	gp.size = Vector2(half * 2.0 + 2.8, 0.12)
	glow.mesh = gp
	glow.material_override = edge
	glow.position = Vector3(0, post_h - 0.32, 0.43)
	root.add_child(glow)

	# 笠木：黑色頂蓋把剪影收成鳥居，夜色裡才不會看成兩根柱子
	var kasagi := MeshInstance3D.new()
	kasagi.mesh = SceneKit.chamfer_box(Vector3(half * 2.0 + 3.6, 0.26, 0.98), 0.05)
	kasagi.material_override = SceneKit.flat_material(Color(0.08, 0.035, 0.03))
	kasagi.position = Vector3(0, post_h + 0.08, 0)
	root.add_child(kasagi)

	# 垂簾
	var rope := MeshInstance3D.new()
	rope.mesh = SceneKit.chamfer_box(Vector3(0.12, 1.7, 0.12), 0.03)
	rope.material_override = SceneKit.flat_material(Color(0.32, 0.28, 0.20))
	rope.position = Vector3(0, post_h - 1.9, 0)
	root.add_child(rope)
	return root


## 路的盡頭固定一座神社。它不跟著路面回收，所以整段路都是在朝它跑。
func _build_shrine() -> void:
	var root := Node3D.new()
	root.position = Vector3(0, 0, -96)
	root.scale = Vector3.ONE * 1.35
	add_child(root)

	var vermilion := SceneKit.flat_material(Color(0.86, 0.16, 0.11))
	var ink := SceneKit.flat_material(Color(0.07, 0.045, 0.06))
	var plaster := SceneKit.flat_material(Color(0.90, 0.88, 0.82))
	var stone := SceneKit.flat_material(Color(0.24, 0.22, 0.28))
	var gold := SceneKit.flat_material(Color(0.93, 0.74, 0.28))
	gold.emission_enabled = true
	gold.emission = Color(0.93, 0.74, 0.28)
	gold.emission_energy_multiplier = 0.55

	for i in 3:
		var step := MeshInstance3D.new()
		step.mesh = SceneKit.chamfer_box(Vector3(11.0 - i * 1.5, 0.28, 2.4), 0.04)
		step.material_override = stone
		step.position = Vector3(0, 0.14 + i * 0.28, 4.6 - i * 1.6)
		root.add_child(step)

	var hall := MeshInstance3D.new()
	hall.mesh = SceneKit.chamfer_box(Vector3(8.6, 4.4, 5.8), 0.08)
	hall.material_override = plaster
	hall.position = Vector3(0, 0.84 + 2.2, -1.4)
	root.add_child(hall)

	for x in [-3.7, 3.7]:
		for z in [1.3, -3.6]:
			var pillar := MeshInstance3D.new()
			pillar.mesh = SceneKit.chamfer_box(Vector3(0.46, 5.6, 0.46), 0.04)
			pillar.material_override = vermilion
			pillar.position = Vector3(x, 0.84 + 2.8, z)
			root.add_child(pillar)

	var roof := MeshInstance3D.new()
	roof.mesh = SceneKit.chamfer_box(Vector3(12.8, 0.55, 8.6), 0.1)
	roof.material_override = ink
	roof.position = Vector3(0, 6.7, -1.2)
	root.add_child(roof)

	for side in [-1.0, 1.0]:
		var eave := MeshInstance3D.new()
		eave.mesh = SceneKit.chamfer_box(Vector3(1.5, 0.72, 8.8), 0.08)
		eave.material_override = ink
		eave.position = Vector3(side * 6.6, 7.25, -1.2)
		eave.rotation.z = side * -0.38
		root.add_child(eave)

	var ridge := MeshInstance3D.new()
	ridge.mesh = SceneKit.chamfer_box(Vector3(0.38, 0.5, 7.4), 0.04)
	ridge.material_override = gold
	ridge.position = Vector3(0, 7.2, -1.2)
	root.add_child(ridge)

	var gate := _make_gate()
	gate.position = Vector3(0, 0, 7.2)
	gate.scale = Vector3(0.62, 0.78, 0.62)
	root.add_child(gate)

	for side in [-1, 1]:
		var lantern := SceneKit.make_lantern()
		lantern.position = Vector3(side * 6.4, 0.2, 5.4)
		root.add_child(lantern)


# ── 路面外的碎裂石板 ──────────────────────────────────────────────────────
func _build_shoulders() -> void:
	var plane := PlaneMesh.new()
	plane.size = Vector2(1.9, 1.9)
	var mats := [
		SceneKit.flat_material(Color(0.11, 0.09, 0.15)),
		SceneKit.flat_material(Color(0.14, 0.11, 0.18)),
		SceneKit.flat_material(Color(0.08, 0.07, 0.12)),
	]
	for side in [-1, 1]:
		var arr: Array[Node3D] = _shoulder_l if side < 0 else _shoulder_r
		for i in 16:
			var mi := MeshInstance3D.new()
			mi.mesh = plane
			mi.material_override = mats[_rng.randi_range(0, 2)]
			mi.position = Vector3(side * _rng.randf_range(6.4, 16.0), 0.0, 0)
			mi.rotation.y = _rng.randf() * TAU
			mi.scale = Vector3.ONE * _rng.randf_range(0.7, 1.7)
			add_child(mi)
			arr.append(mi)


# ── 風切線 ──────────────────────────────────────────────────────────────
func _build_speed_lines() -> void:
	_speed_lines = SceneKit.make_speed_lines(SPEEDLINE_COUNT)
	add_child(_speed_lines)
	_scatter_speed_lines(true)


func _scatter_speed_lines(initial: bool) -> void:
	var mm := _speed_lines.multimesh
	for i in SPEEDLINE_COUNT:
		if not initial and mm.get_instance_transform(i).origin.z < -70.0:
			continue
		var ang := _rng.randf() * TAU
		var r := _rng.randf_range(3.2, 13.0)
		var y := _rng.randf_range(0.4, 7.0)
		var z := _rng.randf_range(-60.0, 12.0)
		var s := _rng.randf_range(0.6, 2.4)
		mm.set_instance_transform(i,
			Transform3D(Basis().scaled(Vector3(s, s * _rng.randf_range(0.8, 2.2), 1.0)),
				Vector3(cos(ang) * r, y, z)))


# ── 漂浮粒子（依單元切換：櫻花 / 火星 / 雪）────────────────────────────
func _build_ambient() -> void:
	_petals = CPUParticles3D.new()
	_petals.amount = 140
	_petals.lifetime = 9.0
	_petals.preprocess = 6.0
	_petals.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	_petals.emission_box_extents = Vector3(22, 9, 26)
	_petals.position = Vector3(0, 5.0, -14)
	_petals.local_coords = false
	_petals.direction = Vector3(0, -1, 0)
	_petals.spread = 40.0
	_petals.gravity = Vector3(0.6, -0.5, 0)
	_petals.initial_velocity_min = 0.4
	_petals.initial_velocity_max = 1.6
	_petals.angular_velocity_min = -90.0
	_petals.angular_velocity_max = 90.0

	var mesh: SphereMesh = SceneKit.blob(0.055, 4, 6).duplicate()
	_petals.mesh = mesh
	mesh.surface_set_material(0, SceneKit.toon_material(Color(1.0, 0.80, 0.90), 0.5, 0.8, 0.18))
	add_child(_petals)


func set_theme(t: int) -> void:
	theme = t
	if _petals == null:
		return
	# 換關卡（清音／濁音／拗音）也會動到同一組粒子，
	# 所以要把當前分區的天氣再套回去，否則換區效果會被洗掉。
	match t:
		1:  # 濁音：火星
			_petals.mesh.surface_set_material(0, SceneKit.toon_material(Color(1.0, 0.45, 0.18), 0.4, 0.9, 3.0))
		2:  # 拗音：雪
			_petals.mesh.surface_set_material(0, SceneKit.toon_material(Color(0.92, 0.96, 1.0), 0.6, 0.6, 0.6))
		_:
			_petals.mesh.surface_set_material(0, SceneKit.toon_material(Color(1.0, 0.80, 0.90), 0.5, 0.8, 0.18))
	if _weather_kind != "":
		set_weather(_weather_kind, _weather_gravity, _weather_tint)
	# 護欄顏色跟區走，不跟單元。單元只改天色和粒子。
	_apply_zone_road()


## 分區天氣：改變粒子的重力、顏色與形狀。
##
## 草木是飄落的花瓣、雨是細長的下落水痕、嵐是橫向的風雨 ——
## 只換顏色看不出來，必須換形狀，遠看才知道換區了。
func set_weather(kind: String, gravity: Vector3, tint: Color) -> void:
	if _petals == null:
		return
	_weather_kind = kind
	_weather_gravity = gravity
	_weather_tint = tint
	_petals.gravity = gravity
	var streak := kind == "rain" or kind == "storm"
	if streak:
		# 細長的方塊往下掉，看起來就是雨絲
		var m := SceneKit.chamfer_box(Vector3(0.035, 1.15, 0.035), 0.01)
		m.surface_set_material(0, SceneKit.toon_material(tint, 0.5, 0.3, 0.85))
		_petals.mesh = m
		_petals.amount = 420 if kind == "rain" else 620
		_petals.initial_velocity_max = 6.0 + gravity.length() * 1.6
		_petals.lifetime = 2.2
	else:
		var m := SceneKit.blob(0.11, 4, 7)
		m.surface_set_material(0, SceneKit.toon_material(tint, 0.6, 0.6, 0.5))
		_petals.mesh = m
		_petals.amount = 140
		_petals.initial_velocity_max = 2.0 + gravity.length() * 1.4
		_petals.lifetime = 9.0
	_petals.preprocess = 4.0


## 四區的路面要一眼分得出來：暖、雨、神社琥珀、嵐。
## 在 set_theme 之後再套一次，單元換軌的顏色才不會把區蓋掉。
func set_zone(zone: int) -> void:
	_zone = clampi(zone, 0, 3)
	_paint_ridges(_zone)
	_apply_zone_road()


func _apply_zone_road() -> void:
	if _road_mat == null:
		return
	match _zone:
		1:
			_road_mat.set_shader_parameter("base_color", Color(0.10, 0.12, 0.16))
			_road_mat.set_shader_parameter("wet_color", Color(0.16, 0.32, 0.52))
			_road_mat.set_shader_parameter("wetness", 0.86)
			_rail_base = Color(0.50, 0.72, 1.0)
		2:
			_road_mat.set_shader_parameter("base_color", Color(0.16, 0.11, 0.12))
			_road_mat.set_shader_parameter("wet_color", Color(0.32, 0.16, 0.12))
			_road_mat.set_shader_parameter("wetness", 0.30)
			_rail_base = Color(1.0, 0.58, 0.26)
		3:
			_road_mat.set_shader_parameter("base_color", Color(0.09, 0.07, 0.10))
			_road_mat.set_shader_parameter("wet_color", Color(0.26, 0.10, 0.14))
			_road_mat.set_shader_parameter("wetness", 0.92)
			_rail_base = Color(1.0, 0.32, 0.36)
		_:
			_road_mat.set_shader_parameter("base_color", Color(0.20, 0.16, 0.18))
			_road_mat.set_shader_parameter("wet_color", Color(0.20, 0.24, 0.28))
			_road_mat.set_shader_parameter("wetness", 0.20)
			_rail_base = Color(0.82, 0.66, 0.36)
	_road_mat.set_shader_parameter("rail_color", _rail_base)


## 連段里程碑：護欄整條亮一下
func flash_rails() -> void:
	_rail_flash = 1.0


# ── 每幀推進 ────────────────────────────────────────────────────────────
func advance(distance: float) -> void:
	var dz := distance
	_travel = fposmod(_travel + distance, ROAD_LENGTH)
	if _road_mat != null:
		_road_mat.set_shader_parameter("travel", _travel)
	_recycle(_dashes, DASH_SPAN * DASH_COUNT, dz)
	_recycle(_lanterns, LANTERN_SPAN * LANTERN_COUNT, dz)
	_recycle(_gates, GATE_SPAN * GATE_COUNT, dz)
	_recycle(_shoulder_l, 9.0 * 16, dz)
	_recycle(_shoulder_r, 9.0 * 16, dz)
	_recycle_speed_lines(dz)
	_tick_rail_flash(dz)


## 連段里程碑的護欄閃光
var _rail_flash := 0.0
var _rail_base := Color(0.42, 0.52, 1.0)

func _tick_rail_flash(dz: float) -> void:
	if _road_mat == null:
		return
	if _rail_flash <= 0.0:
		return
	_rail_flash = maxf(0.0, _rail_flash - dz * 0.35)
	_road_mat.set_shader_parameter("rail_color",
		_rail_base.lerp(Color(0.55, 1.0, 0.80), _rail_flash))


func _recycle(pool: Array[Node3D], span: float, dz: float) -> void:
	for item in pool:
		item.position.z += dz
		if item.position.z > RECYCLE_Z:
			item.position.z -= span


func _recycle_speed_lines(dz: float) -> void:
	var mm := _speed_lines.multimesh
	var amount := int(float(SPEEDLINE_COUNT) * clampf(speed01 * 1.6, 0.0, 1.0))
	for i in SPEEDLINE_COUNT:
		if i >= amount:
			mm.set_instance_transform(i, Transform3D(Basis().scaled(Vector3.ZERO), Vector3(0, -900, 0)))
			continue
		var t := mm.get_instance_transform(i)
		var p := t.origin
		p.z += dz * 1.9
		if p.z > 14.0:
			p.z = -70.0
			var ang := _rng.randf() * TAU
			var r := _rng.randf_range(3.0, 12.0)
			p.x = cos(ang) * r
			p.y = _rng.randf_range(0.4, 7.0)
		t.origin = p
		mm.set_instance_transform(i, t)


func set_speed01(v: float) -> void:
	speed01 = clampf(v, 0.0, 1.0)
	_apply_scroll()


## 完全靜止（倒地結算、三選一、暫停）。
##
## 為什麼需要這個：單純呼叫 set_speed01(0) 並不會讓路面停下來 ——
## scroll_speed 是 lerp(3, 16, speed01)，所以速度歸零時它還是 3，
## 貼圖會繼續滾動，看起來就像輸送帶。地板的滾動必須獨立於「速度」控制。
func set_frozen(on: bool) -> void:
	_frozen = on
	if _petals != null:
		_petals.visible = not on
	if _speed_lines != null:
		_speed_lines.visible = not on
	_apply_scroll()


func _apply_scroll() -> void:
	if _road_mat == null:
		return
	if _frozen:
		_road_mat.set_shader_parameter("scroll_speed", 0.0)
		_road_mat.set_shader_parameter("streak_density", 0.0)
	else:
		_road_mat.set_shader_parameter("scroll_speed", lerpf(3.0, 16.0, speed01))
		_road_mat.set_shader_parameter("streak_density", lerpf(8.0, 26.0, speed01))


func reset() -> void:
	_travel = 0.0
	if _road_mat != null:
		_road_mat.set_shader_parameter("travel", 0.0)
	_rng.seed = randi()
	for d in _dashes:
		d.position.z = _rng.randf_range(-70.0, 20.0)
	for l in _lanterns:
		l.position.z = _rng.randf_range(-70.0, 20.0)
	for g in _gates:
		g.position.z = _rng.randf_range(-150.0, 10.0)
	for s in _shoulder_l:
		s.position.z = _rng.randf_range(-70.0, 20.0)
	for s in _shoulder_r:
		s.position.z = _rng.randf_range(-70.0, 20.0)
	_scatter_speed_lines(true)
