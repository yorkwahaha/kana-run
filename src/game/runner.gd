extends Node3D
## 正後方的跑步立繪。鏡頭在身後，人背對鏡頭往前跑。
##
## 用 QuadMesh 而不是 Sprite3D：倒地測試只量 MeshInstance3D 的包圍盒。
## 腳底放在本地 y=0。倒下、撞飛都換畫好的連續幀，不再把站著的圖轉平。

# 護頭時手比頭頂還高，畫布從 626 加到 667。身高跟著加，人在畫面上的大小才不變。
const FIG_H := 1.78 * 667.0 / 626.0
const GROUND_Y := 0.03

const _RUN: Array[Texture2D] = [
	preload("res://assets/runner/run_0.png"),
	preload("res://assets/runner/run_1.png"),
	preload("res://assets/runner/run_2.png"),
	preload("res://assets/runner/run_3.png"),
	preload("res://assets/runner/run_4.png"),
	preload("res://assets/runner/run_5.png"),
	preload("res://assets/runner/run_6.png"),
	preload("res://assets/runner/run_7.png"),
	preload("res://assets/runner/run_8.png"),
	preload("res://assets/runner/run_9.png"),
	preload("res://assets/runner/run_10.png"),
	preload("res://assets/runner/run_11.png"),
]
const _FALL: Array[Texture2D] = [
	preload("res://assets/runner/fall_0.png"),
	preload("res://assets/runner/fall_1.png"),
	preload("res://assets/runner/fall_2.png"),
	preload("res://assets/runner/fall_3.png"),
	preload("res://assets/runner/fall_4.png"),
	preload("res://assets/runner/fall_5.png"),
	preload("res://assets/runner/fall_6.png"),
	preload("res://assets/runner/fall_7.png"),
	preload("res://assets/runner/fall_8.png"),
	preload("res://assets/runner/fall_9.png"),
]
const _FLING: Array[Texture2D] = [
	preload("res://assets/runner/fling_0.png"),
	preload("res://assets/runner/fling_1.png"),
	preload("res://assets/runner/fling_2.png"),
	preload("res://assets/runner/fling_3.png"),
	preload("res://assets/runner/fling_4.png"),
	preload("res://assets/runner/fling_5.png"),
	preload("res://assets/runner/fling_6.png"),
]
## 撞破石碑時雙手交叉護頭：抬手、停住、再放下。
const GUARD_RAISE := 0.20
const GUARD_HOLD := 0.34
const GUARD_LOWER := 0.18
const GUARD_TIME := GUARD_RAISE + GUARD_HOLD + GUARD_LOWER
const _GUARD: Array[Texture2D] = [
	preload("res://assets/runner/guard_0.png"),
	preload("res://assets/runner/guard_1.png"),
	preload("res://assets/runner/guard_2.png"),
	preload("res://assets/runner/guard_3.png"),
	preload("res://assets/runner/guard_4.png"),
	preload("res://assets/runner/guard_5.png"),
]

var speed01 := 0.0

var _rig: Node3D
var _billboard: MeshInstance3D
var _shadow: MeshInstance3D
var _mat: StandardMaterial3D
var _tex: Texture2D

var _phase := 0.0
var _lane := 0.0
var _target_lane := 0.0
var _duck := 0.0
var _duck_target := 0.0
var _burst := 0.0
var _stagger := 0.0
var _guard := 0.0
var _collapse := 0.0
var _collapse_on := false
var _collapse_flung := false
var _fling_t := 0.0
var _bank := 0.0
var _ground_fix := 0.0
var _scan_low := 0.0


func _ready() -> void:
	_build()


func _build() -> void:
	scale = Vector3.ONE * 1.16

	_shadow = SceneKit.make_contact_shadow(0.62)
	add_child(_shadow)

	var tex := _RUN[0]
	var aspect := tex.get_width() / float(tex.get_height())

	_rig = Node3D.new()
	add_child(_rig)

	var quad := QuadMesh.new()
	quad.size = Vector2(FIG_H * aspect, FIG_H)
	_mat = StandardMaterial3D.new()
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_mat.albedo_texture = tex

	_billboard = MeshInstance3D.new()
	_billboard.mesh = quad
	_billboard.material_override = _mat
	_billboard.position.y = FIG_H * 0.5
	_billboard.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_rig.add_child(_billboard)
	_tex = tex


func set_lane(x: float) -> void:
	_target_lane = x


func set_duck(on: bool) -> void:
	_duck_target = 1.0 if on else 0.0


func burst() -> void:
	_burst = 1.0


func stagger() -> void:
	_stagger = 1.0
	_duck = maxf(_duck, 0.55)
	_duck_target = maxf(_duck_target, 0.55)


## 答對、石碑碎開的一瞬間：雙手交叉擋在腦後。
func guard() -> void:
	_guard = GUARD_TIME
	_stagger = 0.0


## flung=true：被撞飛，人在空中翻出去再趴下。false：體力用盡，往前跪倒。
func collapse(flung := false) -> void:
	_collapse = 0.0
	_collapse_on = true
	_guard = 0.0
	_collapse_flung = flung
	if flung:
		_fling_t = 0.0
		_duck = 0.0
		_duck_target = 0.0
	else:
		_duck = 1.0
		_duck_target = 1.0


func reset() -> void:
	_lane = 0.0
	_target_lane = 0.0
	_duck = 0.0
	_duck_target = 0.0
	_burst = 0.0
	_stagger = 0.0
	_guard = 0.0
	_collapse = 0.0
	_collapse_on = false
	_collapse_flung = false
	_fling_t = 0.0
	_ground_fix = 0.0
	_bank = 0.0
	_phase = 0.0
	position = Vector3.ZERO
	if _rig != null:
		_rig.position = Vector3.ZERO
		_rig.rotation = Vector3.ZERO
	if _billboard != null:
		_billboard.position = Vector3(0, FIG_H * 0.5, 0)
		_billboard.rotation = Vector3.ZERO
		_billboard.scale = Vector3.ONE
	if _shadow != null:
		_shadow.scale = Vector3.ONE
	_set_tex(_RUN[0])


func _process(delta: float) -> void:
	if _collapse_on:
		_process_collapse(delta)
		return

	var prev := _lane
	_lane = lerpf(_lane, _target_lane, clampf(delta * 12.0, 0.0, 1.0))
	var vx := (_lane - prev) / maxf(delta, 0.0001)
	_bank = lerpf(_bank, clampf(-vx * 0.045, -0.42, 0.42), clampf(delta * 9.0, 0.0, 1.0))
	position.x = _lane

	_duck = lerpf(_duck, _duck_target, clampf(delta * 14.0, 0.0, 1.0))
	_burst = maxf(0.0, _burst - delta * 3.2)
	_stagger = maxf(0.0, _stagger - delta * 1.5)
	# 靜止約 0.92 秒一個步伐循環，全速約 0.40 秒。十二幀攤在這一圈上。
	var cycle := lerpf(0.92, 0.40, speed01)
	_phase += delta / cycle
	if _guard > 0.0:
		_guard = maxf(0.0, _guard - delta)
		_draw_guard(GUARD_TIME - _guard)
		_shadow.scale = Vector3.ONE
		return

	var squash := 1.0 - _duck * 0.34
	var bob := absf(sin(_phase * TAU)) * (0.03 + speed01 * 0.035)
	_billboard.scale = Vector3(1.0 + _burst * 0.05, squash, 1.0)
	_billboard.position.y = FIG_H * 0.5 * squash + bob
	_billboard.rotation = Vector3(-0.03 - speed01 * 0.04, 0.0, _stagger * 0.18)
	var frame := int(_phase * float(_RUN.size())) % _RUN.size()
	_set_tex(_RUN[frame])
	_rig.rotation = Vector3(-_stagger * 0.12, _bank * 0.35, _bank)
	_shadow.scale = Vector3.ONE * (1.0 - _duck * 0.22)


func _draw_guard(elapsed: float) -> void:
	var n := _GUARD.size()
	var idx := n - 1
	if elapsed < GUARD_RAISE:
		idx = mini(int(elapsed / GUARD_RAISE * float(n)), n - 1)
	elif elapsed >= GUARD_RAISE + GUARD_HOLD:
		var u := clampf((elapsed - GUARD_RAISE - GUARD_HOLD) / GUARD_LOWER, 0.0, 1.0)
		idx = n - 1 - mini(int(u * float(n)), n - 1)
	_set_tex(_GUARD[idx])
	_billboard.scale = Vector3(1.0 + _burst * 0.04, 1.0, 1.0)
	_billboard.position.y = FIG_H * 0.5
	_billboard.rotation = Vector3.ZERO
	_rig.rotation = Vector3(0.0, _bank * 0.25, _bank * 0.6)


func _process_collapse(delta: float) -> void:
	if _collapse_flung:
		_process_fling(delta)
		return
	_collapse = minf(1.0, _collapse + delta / 1.15)
	var idx := mini(int(_collapse * float(_FALL.size())), _FALL.size() - 1)
	_set_tex(_FALL[idx])
	position.x = _lane
	_rig.rotation = Vector3(lerpf(0.0, 0.12, _collapse), 0.0, _bank * (1.0 - _collapse))
	_billboard.scale = Vector3.ONE
	_billboard.position.y = FIG_H * 0.5
	_billboard.rotation = Vector3.ZERO
	var gs := 1.0 if _collapse >= 0.995 else clampf(delta * 14.0, 0.0, 1.0)
	_settle_ground(gs)
	_shadow.scale = Vector3.ONE * lerpf(1.0, 0.62, _collapse)


## 被撞飛：往前 5.6 公尺、拋高 1.3。空中播翻轉的幀，落地播趴下的那一張。
func _process_fling(delta: float) -> void:
	_fling_t += delta
	var flight := 0.72
	var air := _FLING.size() - 1
	position.x = _lane
	_billboard.scale = Vector3.ONE
	_billboard.rotation = Vector3.ZERO
	_billboard.position.y = FIG_H * 0.5
	if _fling_t < flight:
		var u := _fling_t / flight
		position.z = -5.6 * u
		position.y = sin(PI * u) * 1.3
		_rig.rotation = Vector3(0.0, 0.0, sin(u * PI) * 0.1)
		_set_tex(_FLING[mini(int(u * float(air)), air - 1)])
		_shadow.scale = Vector3.ONE * (1.0 - 0.55 * sin(PI * u))
	else:
		var u := clampf((_fling_t - flight) / 0.3, 0.0, 1.0)
		var e := 1.0 - pow(1.0 - u, 3.0)
		position.z = -5.6
		position.y = -0.04 * (1.0 - e)
		_rig.rotation = Vector3.ZERO
		_set_tex(_FLING[_FLING.size() - 1])
		var gs := 1.0 if _fling_t >= flight + 0.3 else clampf(delta * 12.0, 0.0, 1.0)
		_settle_ground(gs)
		_shadow.scale = Vector3.ONE * lerpf(0.7, 1.15, e)


func _set_tex(tex: Texture2D) -> void:
	if _mat == null or tex == _tex:
		return
	_tex = tex
	_mat.albedo_texture = tex


func _scan_lowest(r: Node) -> void:
	if r is MeshInstance3D:
		var mi := r as MeshInstance3D
		if mi.visible and mi.mesh != null:
			var bb := mi.global_transform * mi.get_aabb()
			_scan_low = minf(_scan_low, bb.position.y)
	for c in r.get_children():
		_scan_lowest(c)


func _settle_ground(strength := 1.0) -> void:
	_scan_low = INF
	_scan_lowest(_rig)
	_ground_fix += (GROUND_Y - _scan_low) / maxf(scale.y, 0.001) * clampf(strength, 0.0, 1.0)
	_rig.position.y = _ground_fix
