extends Node3D
## Crossbar — 攔在跑道上的矮欄，擋住其中兩條道、留一條空的。
##
## 為什麼需要：一局 46 題原本全是「看題 → 換線 → 撞碑」同一個動作，
## 閃避機制寫好了卻沒有任何東西會要求你閃，等於整個機制是死的。
##
## 設計重點：橫桿**只擋其中兩條跑道**。
## 如果它橫跨整條路，三條道都必須蹲 —— 那就只是按一下按鈕，
## 沒有判斷可言，玩家很快就會無腦按。留一條空的之後才變成真正的選擇：
##   換到綠色那條空道 → 正常作答、拿分、連段繼續
##   待在被紅白條擋的道上蹲 → 閃過了，但這題作廢（不計分、requeue）
##
## 顏色即語言：紅白警示 = 必須蹲，綠色矮欄 = 站著直接過。

const BLOCK_H := 1.34        ## 紅白條的下緣高度（擋路）
const BLOCK_BAR_H := 0.28
const OPEN_H := 0.30         ## 綠色矮欄高度，遠低於站立高度
const LANE_W := 2.55         ## 每條道的欄杆寬度
const POST_W := 0.22

var passed := false
var blocked := 0             ## bitmask：第 i 個 bit 為 1 表示第 i 條道被擋

var _blocked_lanes: Array[Node3D] = []
var _open_lanes: Array[Node3D] = []
var _lanterns: Array[MeshInstance3D] = []
var _hit_lane := -1
var _swing := 0.0
var _t := 0.0
var _hit_t := 0.0
var _cleared := false
var _lane_x: Array = []


## 這條道需要蹲嗎？
func blocks(lane: int) -> bool:
	return (blocked & (1 << lane)) != 0


func _ready() -> void:
	_build()


func _build() -> void:
	var wood := SceneKit.toon_material(Color(0.34, 0.26, 0.17), 0.75, 0.72)
	var danger := SceneKit.toon_material(Color(0.88, 0.18, 0.26), 0.95, 0.55, 0.55)
	var white := SceneKit.toon_material(Color(0.97, 0.97, 1.0), 0.8, 0.5, 0.4)
	var safe := SceneKit.toon_material(Color(0.32, 0.96, 0.68), 1.1, 0.45, 1.3)

	for i in 3:
		_blocked_lanes.append(_build_blocked(wood, danger, white))
		_open_lanes.append(_build_open(safe))

	visible = false


## 紅白警示段：立柱 + 橫桿 + 交錯布條 + 吊燈 = 「這裡必須蹲」
func _build_blocked(wood: Material, danger: Material, white: Material) -> Node3D:
	var root := Node3D.new()
	add_child(root)
	for side in [-1, 1]:
		var post := MeshInstance3D.new()
		post.mesh = SceneKit.chamfer_box(Vector3(POST_W, BLOCK_H + 0.42, POST_W), 0.05)
		post.material_override = wood
		post.position = Vector3(side * LANE_W * 0.5, (BLOCK_H + 0.42) * 0.5, 0)
		root.add_child(post)
	var bar := MeshInstance3D.new()
	bar.mesh = SceneKit.chamfer_box(Vector3(LANE_W + POST_W, BLOCK_BAR_H, POST_W * 0.85), 0.05)
	bar.material_override = danger
	bar.position = Vector3(0, BLOCK_H + BLOCK_BAR_H * 0.5, 0)
	root.add_child(bar)
	var n := 6
	for k in n:
		var strip := MeshInstance3D.new()
		strip.mesh = SceneKit.chamfer_box(
			Vector3(LANE_W / float(n) * 0.82, BLOCK_BAR_H * 0.66, POST_W * 0.95), 0.012)
		strip.material_override = danger if k % 2 == 0 else white
		strip.position = Vector3(
			-LANE_W * 0.5 + (LANE_W / float(n)) * (float(k) + 0.5),
			BLOCK_H + BLOCK_BAR_H * 0.5, 0)
		root.add_child(strip)
	var lan := MeshInstance3D.new()
	lan.mesh = SceneKit.blob(0.24, 6, 10)
	lan.material_override = SceneKit.toon_material(Color(1.0, 0.58, 0.28), 1.0, 0.4, 2.6)
	lan.scale = Vector3(1.0, 1.3, 1.0)
	lan.position = Vector3(-LANE_W * 0.5 + 0.1, BLOCK_H - 0.26, 0)
	root.add_child(lan)
	_lanterns.append(lan)
	return root


## 綠色矮欄 + 地面箭頭 = 「站著直接過」
func _build_open(safe: Material) -> Node3D:
	var root := Node3D.new()
	add_child(root)
	var low := MeshInstance3D.new()
	low.mesh = SceneKit.chamfer_box(Vector3(LANE_W + POST_W, 0.14, POST_W * 0.8), 0.04)
	low.material_override = safe
	low.position = Vector3(0, OPEN_H + 0.07, 0)
	root.add_child(low)
	for k in 3:
		var mark := MeshInstance3D.new()
		mark.mesh = SceneKit.chamfer_box(Vector3(0.34, 0.03, 0.5), 0.01)
		mark.material_override = safe
		mark.position = Vector3(0, 0.03, -1.2 + float(k) * 1.2)
		root.add_child(mark)
	return root


## covered：bitmask，1 = 該道被擋。lane_x：三條道的中心 x 座標。
func setup(covered: int, lane_x: Array = []) -> void:
	blocked = covered
	_lane_x = lane_x
	visible = true
	passed = false
	_cleared = false
	_t = 0.0
	_swing = 0.0
	_hit_t = 0.0
	_hit_lane = -1
	for i in 3:
		var x: float = float(_lane_x[i]) if i < _lane_x.size() else 0.0
		var is_blocked := blocks(i)
		_blocked_lanes[i].position = Vector3(x, 0, 0)
		_open_lanes[i].position = Vector3(x, 0, 0)
		_blocked_lanes[i].visible = is_blocked
		_open_lanes[i].visible = not is_blocked
	scale = Vector3.ONE
	position.y = 0.0


## 蹲下通過 → 所在走道的吊燈轉綠並往上彈一下
func mark_cleared(lane: int) -> void:
	if _cleared:
		return
	_cleared = true
	passed = true
	_swing = 1.0
	if lane >= 0 and lane < _lanterns.size():
		_lanterns[lane].material_override = \
			SceneKit.toon_material(Color(0.45, 1.0, 0.65), 1.2, 0.4, 3.0)


## 撞上去 → 那一段的橫桿歪掉並往下沉
func mark_hit(lane: int) -> void:
	if passed:
		return
	passed = true
	_hit_lane = lane


func _process(delta: float) -> void:
	if not visible:
		return
	_t += delta
	for i in _lanterns.size():
		_lanterns[i].rotation.z = sin(_t * 2.4 + i * PI) * 0.16
	if _hit_lane >= 0 and _hit_lane < _blocked_lanes.size():
		_hit_t = minf(1.0, _hit_t + delta * 2.6)
		var e := 1.0 - pow(1.0 - _hit_t, 3.0)
		_blocked_lanes[_hit_lane].rotation.z = 0.30 * e
		_blocked_lanes[_hit_lane].position.y = -0.75 * e
	if _swing > 0.0:
		_swing = maxf(0.0, _swing - delta * 3.2)
