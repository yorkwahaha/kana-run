extends Node3D
## 背面的跑步立繪。鏡頭在身後，側面的圖會像橫著跑過馬路。
##
## 用 QuadMesh 而不是 Sprite3D：倒地測試只量 MeshInstance3D 的包圍盒。
## 腳底放在本地 y=0。撞飛時整個 rig 繞 X 轉到 -90°，人就趴在路面上。

const FIG_H := 1.78
const GROUND_Y := 0.03

var speed01 := 0.0

var _rig: Node3D
var _billboard: MeshInstance3D
var _shadow: MeshInstance3D
var _mat: StandardMaterial3D
var _frames: Array[Texture2D] = []
var _frame := -1

var _phase := 0.0
var _lane := 0.0
var _target_lane := 0.0
var _duck := 0.0
var _duck_target := 0.0
var _burst := 0.0
var _stagger := 0.0
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

	_frames = [
		preload("res://assets/runner/run_0.png"),
		preload("res://assets/runner/run_1.png"),
	]
	var tex := _frames[0]
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
	_frame = 0


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


## flung=true：被撞飛後趴在路上。false：體力用盡，往前折下去。
func collapse(flung := false) -> void:
	_collapse = 0.0
	_collapse_on = true
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
	_phase += delta * (5.4 + speed01 * 7.6)

	var squash := 1.0 - _duck * 0.34
	var bob := absf(sin(_phase)) * (0.03 + speed01 * 0.035)
	_billboard.scale = Vector3(1.0 + _burst * 0.05, squash, 1.0)
	_billboard.position.y = FIG_H * 0.5 * squash + bob
	_billboard.rotation = Vector3(-0.08 - speed01 * 0.12, 0.0, _stagger * 0.35)
	_set_frame(0 if sin(_phase) >= 0.0 else 1)
	_rig.rotation = Vector3(-_stagger * 0.22, _bank * 0.35, _bank)
	_shadow.scale = Vector3.ONE * (1.0 - _duck * 0.22)


func _process_collapse(delta: float) -> void:
	if _collapse_flung:
		_process_fling(delta)
		return
	_collapse = minf(1.0, _collapse + delta / 1.4)
	var t := _collapse
	var stumble := clampf(t / 0.28, 0.0, 1.0)
	var sink := clampf((t - 0.22) / 0.55, 0.0, 1.0)
	var ease := 1.0 - pow(1.0 - sink, 3.0)
	position.x = _lane
	_rig.rotation = Vector3(
		lerpf(0.0, 0.45, stumble) * (1.0 - ease) - ease * 0.15,
		0.0,
		_bank * (1.0 - ease))
	var fold := lerpf(1.0, 0.72, ease)
	_billboard.scale = Vector3(1.0, fold, 1.0)
	_billboard.position.y = FIG_H * 0.5 * fold
	_billboard.rotation = Vector3(lerpf(0.0, -0.85, ease), 0.0, 0.0)
	_set_frame(0)
	var gs := 1.0 if _collapse >= 0.995 else clampf(delta * 14.0, 0.0, 1.0)
	_settle_ground(gs)
	_shadow.scale = Vector3.ONE * (1.0 - 0.25 * ease)


## 被撞飛：往前 5.6 公尺、拋高 1.3，空中翻到面朝下，落地後貼著路面。
func _process_fling(delta: float) -> void:
	_fling_t += delta
	var flight := 0.62
	position.x = _lane
	_billboard.scale = Vector3.ONE
	_billboard.rotation = Vector3.ZERO
	_billboard.position.y = FIG_H * 0.5
	_set_frame(1)
	if _fling_t < flight:
		var u := _fling_t / flight
		position.z = -5.6 * u
		position.y = sin(PI * u) * 1.3
		_rig.rotation = Vector3(-u * PI * 2.5, 0.0, -0.18 * u + sin(u * PI) * 0.30)
	else:
		var u := clampf((_fling_t - flight) / 0.34, 0.0, 1.0)
		var e := 1.0 - pow(1.0 - u, 3.0)
		position.z = -5.6
		position.y = -0.06 * (1.0 - e)
		_rig.rotation = Vector3(-PI * 0.5, 0.0, lerpf(-0.18, 0.12, e))
		var gs := 1.0 if _fling_t >= flight + 0.34 else clampf(delta * 12.0, 0.0, 1.0)
		_settle_ground(gs)
	_shadow.scale = Vector3.ONE * (1.0 - 0.15 * clampf(_fling_t / 0.6, 0.0, 1.0))


func _set_frame(i: int) -> void:
	i = posmod(i, _frames.size())
	if i == _frame:
		return
	_frame = i
	_mat.albedo_texture = _frames[i]


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
