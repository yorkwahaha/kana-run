extends Node3D
## Runner — 程序化組裝的跑者，全部用基本幾何 + 程式動畫。
##
## 沒有骨骼動畫檔，但兩段式四肢、擺動的馬尾、依速度前傾的軀幹，
## 加起來足以讓角色在夜跑道上有存在感。

const HIP_Y := 0.92
const THIGH := 0.44
const SHIN := 0.42
const UPPER_ARM := 0.30
const FOREARM := 0.28

const COL_JACKET := Color(0.90, 0.91, 0.97)
const COL_SKIRT := Color(0.13, 0.14, 0.34)
const COL_LEG := Color(0.80, 0.82, 0.90)
const COL_SHOE := Color(0.30, 0.46, 1.00)
const COL_HAIR := Color(0.26, 0.145, 0.10)
const COL_SCARF := Color(0.62, 0.40, 1.00)
const COL_BAG := Color(0.20, 0.22, 0.46)
const COL_SKIN := Color(0.98, 0.84, 0.74)
const COL_GLOVE := Color(0.24, 0.20, 0.40)

var speed01 := 0.0

var _rig: Node3D
var _hips: Node3D
var _torso: Node3D
var _head: Node3D
var _arm_l: Node3D
var _arm_r: Node3D
var _forearm_l: Node3D
var _forearm_r: Node3D
var _leg_l: Node3D
var _leg_r: Node3D
var _shin_l: Node3D
var _shin_r: Node3D
var _ponytail: Array[Node3D] = []
var _tail_spring: Array[float] = [0.0, 0.0, 0.0]
var _tail_vel: Array[float] = [0.0, 0.0, 0.0]
var _scarf: MeshInstance3D
var _shadow: MeshInstance3D
var _skirt: MeshInstance3D

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


func _ready() -> void:
	_build()


func _limb(parent: Node3D, length: float, radius: float, color: Color, from_top := true) -> Node3D:
	var pivot := Node3D.new()
	parent.add_child(pivot)
	var mesh := MeshInstance3D.new()
	var cap := SceneKit.blob(radius, 6, 10).duplicate() as SphereMesh
	cap.height = length * 2.0
	cap.radius = radius
	cap.surface_set_material(0, SceneKit.toon_material(color, 0.85, 0.6))
	mesh.mesh = cap
	mesh.position.y = (-length * 0.5) if from_top else (length * 0.5)
	mesh.scale = Vector3(1.0, 1.0, 0.92)
	pivot.add_child(mesh)
	return pivot


## 壓扁的球：用來做軀幹、頭顱這類有機形體
func _blob_part(parent: Node3D, radius: float, squash: Vector3, color: Color,
		pos := Vector3.ZERO, rings := 8, segments := 12) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var sm := SceneKit.blob(radius, rings, segments).duplicate() as SphereMesh
	sm.surface_set_material(0, SceneKit.toon_material(color, 0.9, 0.55))
	mi.mesh = sm
	mi.scale = squash
	mi.position = pos
	parent.add_child(mi)
	return mi


func _build() -> void:
	# 整體略微放大：在手機與低解析視窗下角色才讀得出細節
	scale = Vector3.ONE * 1.16

	_shadow = SceneKit.make_contact_shadow(0.70)
	add_child(_shadow)

	_rig = Node3D.new()
	add_child(_rig)

	_hips = Node3D.new()
	_hips.position.y = HIP_Y
	_rig.add_child(_hips)

	# 骨盆
	_blob_part(_hips, 0.17, Vector3(1.25, 0.72, 0.95), COL_SKIRT, Vector3.ZERO, 6, 10)

	# 百褶裙（上窄下寬的圓錐）
	_skirt = MeshInstance3D.new()
	var cone := CylinderMesh.new()
	cone.top_radius = 0.19
	cone.bottom_radius = 0.33
	cone.height = 0.34
	cone.radial_segments = 18
	cone.surface_set_material(0, SceneKit.toon_material(COL_SKIRT, 0.95, 0.6))
	_skirt.mesh = cone
	_skirt.position.y = 0.10
	_hips.add_child(_skirt)

	_torso = Node3D.new()
	_torso.position.y = 0.16
	_hips.add_child(_torso)

	# 上衣
	_blob_part(_torso, 0.185, Vector3(1.06, 1.50, 0.80), COL_JACKET, Vector3(0, 0.30, 0))
	# 衣襬與領口的深色滾邊，讓白上衣在夜色中有輪廓
	var hem := MeshInstance3D.new()
	hem.mesh = SceneKit.blob(0.17, 5, 10)
	hem.material_override = SceneKit.toon_material(Color(0.16, 0.17, 0.32), 0.5, 0.6)
	hem.scale = Vector3(1.12, 0.28, 0.86)
	hem.position = Vector3(0, 0.06, 0)
	_torso.add_child(hem)

	# 書包（背在 +z，也就是朝向鏡頭的那一面）
	# 角色朝 -z 跑，鏡頭在 +z，所以「背」是正 z。
	# 原本背包放在 -z，等於把書包掛在胸前，鏡頭整個看到的是正面，
	# 這才是「看起來像倒著跑」的主因。
	var bag := MeshInstance3D.new()
	var bm := SceneKit.chamfer_box(Vector3(0.30, 0.34, 0.18), 0.05)
	bag.mesh = bm
	bag.material_override = SceneKit.toon_material(COL_BAG, 0.85, 0.6)
	bag.position = Vector3(0, 0.32, 0.19)
	_torso.add_child(bag)
	# 背帶：兩條斜過肩膀的細帶，讓「這是背影」更明確
	for side in [-1, 1]:
		var strap := MeshInstance3D.new()
		strap.mesh = SceneKit.chamfer_box(Vector3(0.055, 0.30, 0.05), 0.02)
		strap.material_override = SceneKit.toon_material(Color(0.30, 0.22, 0.52), 0.7, 0.6)
		strap.position = Vector3(side * 0.115, 0.40, 0.10)
		strap.rotation.x = 0.28
		_torso.add_child(strap)

	# 領巾
	_scarf = MeshInstance3D.new()
	var sm := SceneKit.chamfer_box(Vector3(0.30, 0.13, 0.24), 0.05)
	_scarf.mesh = sm
	_scarf.material_override = SceneKit.toon_material(COL_SCARF, 1.1, 0.5, 0.25)
	_scarf.position = Vector3(0, 0.55, 0.02)
	_torso.add_child(_scarf)

	# 頭
	_head = Node3D.new()
	_head.position = Vector3(0, 0.66, 0)
	_torso.add_child(_head)

	_blob_part(_head, 0.128, Vector3(0.94, 1.10, 0.94), COL_SKIN, Vector3.ZERO)
	# 遊戲裡幾乎只看得到她的背面，所以頭髮要往後腦勺（+z）包、往上蓋滿，
	# 否則後腦勺會露出一塊膚色球，看起來像禿頭。
	_blob_part(_head, 0.152, Vector3(1.02, 0.95, 1.06), COL_HAIR, Vector3(0, 0.022, 0.045))
	# 頭頂的馬尾根部結 + 兩側的髮束 + 耳朵：
	# 從正後方看，如果只是個球就分不出正反面，這幾個凸起是方向線索。
	_blob_part(_head, 0.075, Vector3(1.0, 0.8, 1.0), COL_HAIR, Vector3(0, 0.10, 0.10), 6, 10)
	for side in [-1, 1]:
		_blob_part(_head, 0.085, Vector3(0.75, 1.35, 1.05), COL_HAIR,
			Vector3(side * 0.105, 0.01, 0.03), 5, 8)
		_blob_part(_head, 0.036, Vector3(0.55, 1.0, 0.85), COL_SKIN,
			Vector3(side * 0.118, 0.005, -0.01), 5, 7)

	# 馬尾：三節彈簧鏈，跟著跑動甩動
	# 錨點在後腦勺（+z）。原本放在 -z，馬尾就跑到頭的後方被整個遮住，
	# 畫面上等於沒有馬尾，自然也讀不出跑步方向。
	var anchor := Node3D.new()
	anchor.position = Vector3(0, 0.05, 0.13)
	_head.add_child(anchor)
	var parent: Node3D = anchor
	for i in 3:
		var seg := Node3D.new()
		seg.position = Vector3(0, 0, 0.09 if i == 0 else 0.0)
		parent.add_child(seg)
		_blob_part(seg, 0.052 - i * 0.010, Vector3.ONE, COL_HAIR,
			Vector3(0, 0, 0.055), 5, 8)
		_ponytail.append(seg)
		parent = seg

	# 手臂
	_arm_l = _limb(_torso, UPPER_ARM, 0.058, COL_JACKET)
	_arm_l.position = Vector3(-0.22, 0.50, 0)
	_forearm_l = _limb(_arm_l, FOREARM, 0.050, COL_SKIN)
	_add_hand(_forearm_l)
	_arm_r = _limb(_torso, UPPER_ARM, 0.058, COL_JACKET)
	_arm_r.position = Vector3(0.22, 0.50, 0)
	_forearm_r = _limb(_arm_r, FOREARM, 0.050, COL_SKIN)
	_add_hand(_forearm_r)

	# 腿
	_leg_l = _limb(_hips, THIGH, 0.072, COL_LEG)
	_leg_l.position = Vector3(-0.10, 0.02, 0)
	_shin_l = _limb(_leg_l, SHIN, 0.058, COL_LEG)
	_leg_r = _limb(_hips, THIGH, 0.072, COL_LEG)
	_leg_r.position = Vector3(0.10, 0.02, 0)
	_shin_r = _limb(_leg_r, SHIN, 0.058, COL_LEG)

	_add_shoe(_shin_l, -1)
	_add_shoe(_shin_r, 1)


## 手套：原本只有一段膚色前臂，兩隻亮橘色的手會在畫面中央
## 一直晃，看起來像在對鏡頭招手。加深色手套後手腳的對比清楚，畫面也乾淨。
func _add_hand(forearm: Node3D) -> void:
	var hand := MeshInstance3D.new()
	var sm := SceneKit.blob(0.062, 5, 9).duplicate() as SphereMesh
	sm.surface_set_material(0, SceneKit.toon_material(COL_GLOVE, 0.7, 0.55))
	hand.mesh = sm
	hand.scale = Vector3(1.0, 1.15, 0.85)
	hand.position = Vector3(0, -FOREARM - 0.045, 0.01)
	forearm.add_child(hand)


## 球鞋：對稱的盒子看不出朝向，所以做出「腳尖往前、鞋跟在後」的形狀，
## 並在鞋跟加一塊會發亮的反光片。從背面看，抬腳時鞋跟閃一下，
## 跑動方向立刻清楚 —— 這是讓角色不再看起來倒著跑最有效的一招。
func _add_shoe(shin: Node3D, _side: int) -> void:
	var base := Vector3(0, -SHIN - 0.03, 0)
	var shoe := MeshInstance3D.new()
	var sm := SceneKit.chamfer_box(Vector3(0.14, 0.095, 0.30), 0.035)
	shoe.mesh = sm
	shoe.material_override = SceneKit.toon_material(COL_SHOE, 0.9, 0.45, 0.15)
	# 整隻鞋往 -z（遠離鏡頭）推，腳尖才有指向前方的長度
	shoe.position = base + Vector3(0, 0, -0.045)
	shin.add_child(shoe)

	# 白色中底：從背面看是一條亮線，強化腳的輪廓
	var sole := MeshInstance3D.new()
	sole.mesh = SceneKit.chamfer_box(Vector3(0.145, 0.035, 0.31), 0.02)
	sole.material_override = SceneKit.toon_material(Color(0.94, 0.95, 1.0), 0.7, 0.5, 0.1)
	sole.position = base + Vector3(0, -0.055, -0.045)
	shin.add_child(sole)

	# 鞋跟反光片：抬腳時朝鏡頭亮起
	var heel := MeshInstance3D.new()
	heel.mesh = SceneKit.chamfer_box(Vector3(0.10, 0.06, 0.05), 0.02)
	heel.material_override = SceneKit.toon_material(Color(0.70, 0.95, 1.0), 1.4, 0.4, 0.7)
	heel.position = base + Vector3(0, 0.02, 0.105)
	shin.add_child(heel)


# ── 控制 ────────────────────────────────────────────────────────────────
func set_lane(x: float) -> void:
	_target_lane = x


func set_duck(on: bool) -> void:
	_duck_target = 1.0 if on else 0.0


func burst() -> void:
	_burst = 1.0


## 被撞到時踉蹌一下。答錯只有扣分數與體力的話，感覺不到失敗的重量。
func stagger() -> void:
	_stagger = 1.0
	_duck = maxf(_duck, 0.55)
	_duck_target = maxf(_duck_target, 0.55)


## 體力用盡：跪坐在路中間。直接跳結算畫面會讓失敗毫無重量，
## 先讓角色真的撐不住跪下來、跑道停下來，節奏才收得住。
##
## flung=true 代表「是撞到沒體力」：被撞飛出去，趴在地上。
## 兩種結局差在節奏與情緒，不是一個換貼圖而已。
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
	_rig.position.y = 0.0
	_phase = 0.0
	position.x = 0.0
	position.z = 0.0


func _process(delta: float) -> void:
	if _collapse_on:
		_process_collapse(delta)
		return

	# 換線：彈性阻尼，帶一點側傾
	var prev := _lane
	_lane = lerpf(_lane, _target_lane, clampf(delta * 12.0, 0.0, 1.0))
	var vx := (_lane - prev) / maxf(delta, 0.0001)
	_bank = lerpf(_bank, clampf(-vx * 0.045, -0.42, 0.42), clampf(delta * 9.0, 0.0, 1.0))
	position.x = _lane
	_rig.rotation.z = _bank
	_rig.rotation.y = _bank * 0.55

	_duck = lerpf(_duck, _duck_target, clampf(delta * 14.0, 0.0, 1.0))
	_burst = maxf(0.0, _burst - delta * 3.2)
	_stagger = maxf(0.0, _stagger - delta * 1.5)

	# 跑步週期：越快踏得越急
	_phase += delta * (5.4 + speed01 * 7.6)

	var cyc := _phase
	var lean := -0.10 - speed01 * 0.30 - _burst * 0.24
	var bob := absf(sin(cyc)) * (0.045 + speed01 * 0.05)

	_hips.position.y = HIP_Y + bob - _duck * 0.42
	_hips.rotation.x = lean * 0.4
	_torso.rotation.x = lean * 0.6
	_torso.rotation.z = sin(cyc) * 0.05 + _stagger * 0.55
	_torso.rotation.y = -sin(cyc) * 0.10
	# 被撞到時往後仰一下，是「失敗看得見」的最主要來源
	_hips.position.z = -_stagger * 0.22
	_rig.rotation.x = -_stagger * 0.30
	# 頭往前看：從背面看不到臉，頭頸的前傾與側轉是唯一能讀出
	# 「朝前跑」的線索，所以比身體多轉一點。
	_head.rotation.x = -lean * 0.55 + sin(cyc * 2.0) * 0.03
	_head.rotation.y = -_bank * 1.6 - sin(cyc) * 0.06
	_scarf.rotation.x = -0.5 - speed01 * 0.5 + sin(cyc * 1.7) * 0.18

	# 手臂：與腿反相
	# z 旋轉方向原本寫反，兩隻手會往身體中線交叉、在胸前招手。
	# 左臂掛在 -x，要 -z 旋轉才是往外張。
	var swing := 0.75 + speed01 * 0.45
	var ph := sin(cyc)
	_arm_l.rotation.x = ph * swing
	_arm_r.rotation.x = -ph * swing
	_arm_l.rotation.z = -0.20 - _duck * 0.55
	_arm_r.rotation.z = 0.20 + _duck * 0.55
	# 手肘上限壓在約 63°：折到接近 90° 時前臂會正對鏡頭，看起來在招手。
	# 折彎量在「往後擺」（推進期）最大、往前擺（回收期）伸直，才像短跑選手。
	var bend_max := 0.75 + speed01 * 0.35
	_forearm_l.rotation.x = -bend_max * (0.55 + 0.45 * maxf(0.0, -ph))
	_forearm_r.rotation.x = -bend_max * (0.55 + 0.45 * maxf(0.0, ph))

	# 腿：大腿擺動 + 小腿只在後踢時彎曲（避免穿插）
	for s in [-1, 1]:
		var p := cyc if s > 0 else cyc + PI
		var thigh := sin(p) * (0.55 + speed01 * 0.42)
		var knee := maxf(0.0, -cos(p)) * (0.95 + speed01 * 0.75)
		if s < 0:
			_leg_l.rotation.x = thigh
			_shin_l.rotation.x = -knee
		else:
			_leg_r.rotation.x = thigh
			_shin_r.rotation.x = -knee

	# 蹲下時額外收腿
	if _duck > 0.01:
		_hips.rotation.x = lerpf(_hips.rotation.x, 0.55, _duck)
		_leg_l.rotation.x = lerpf(_leg_l.rotation.x, 1.15, _duck)
		_leg_r.rotation.x = lerpf(_leg_r.rotation.x, 1.15, _duck)
		_shin_l.rotation.x = lerpf(_shin_l.rotation.x, -1.75, _duck)
		_shin_r.rotation.x = lerpf(_shin_r.rotation.x, -1.75, _duck)

	_animate_tail(delta)
	_shadow.scale = Vector3.ONE * (1.0 - _duck * 0.25)


## 馬尾：以彈簧模擬逐節落後，轉向與加速時自然甩動
## 被撞飛：沿著 -z（往前）飛一段拋物線，然後趴在地上不動。
##
## 分兩段：0.62 秒的自由落體（往前 5.6 公尺、拋高 1.3，空中翻滾兩圈半），
## 落地瞬間身體轉成面朝下、往前趴，之後只剩微弱的呼吸起伏。
## 距離刻意拉得夠遠 —— 只往前一點點看起來會像「在原地倒下」而不是被撞飛。
func _process_fling(delta: float) -> void:
	_fling_t += delta
	var FLIGHT := 0.62
	position.x = _lane

	if _fling_t < FLIGHT:
		var t := _fling_t / FLIGHT
		# 水平勻速往前，垂直拋物線
		position.z = -5.6 * t
		position.y = sin(PI * t) * 1.3
		# 空中身體轉到水平，落地時剛好面朝下、頭往前。
		# 角度要用負的四分之一圈：繞 X 轉 +90° 會讓臉朝上（變成仰躺）。
		# 總共轉 2.5 圈：2 圈是「翻滾」，多出來的半圈讓落地時剛好是 -90°，
		# 和趴地姿勢完全接得上 —— 若只轉 1 圈，落地瞬間會整個人瞬間翻面 180°。
		_rig.rotation.x = -t * PI * 2.5
		_rig.rotation.z = -0.18 * t + sin(t * PI) * 0.30
		_hips.position.y = HIP_Y
		_hips.position.z = 0.0
		_hips.rotation.x = 0.0
		_torso.rotation.x = -0.15
		_torso.rotation.z = 0.0
		_head.rotation.x = 0.0
		_arm_l.rotation.x = 0.9 * t
		_arm_r.rotation.x = 0.75 * t
		_arm_l.rotation.z = -0.35 - 0.25 * t
		_arm_r.rotation.z = 0.35 + 0.25 * t
		_forearm_l.rotation.x = -0.7 * t
		_forearm_r.rotation.x = -0.7 * t
		_leg_l.rotation.x = -0.55 * t
		_leg_r.rotation.x = -0.35 * t
		_shin_l.rotation.x = 0.6 * t
		_shin_r.rotation.x = 0.45 * t
		_scarf.rotation.x = -1.1 * t
	else:
		# 落地：趴在地上。膝蓋先著地所以整個身體比跪姿更低。
		var t := clampf((_fling_t - FLIGHT) / 0.34, 0.0, 1.0)
		var e := 1.0 - pow(1.0 - t, 3.0)
		position.z = -5.6
		position.y = -0.06 * (1.0 - e)
		_rig.rotation.x = -PI * 0.5
		# 空中最後一幀的 z 角是 -0.18，趴地是 0.12，中間插值才不會瞬間歪一下
		_rig.rotation.z = lerpf(-0.18, 0.12, e)
		_hips.position.y = lerpf(HIP_Y, 0.26, e)
		_hips.rotation.x = lerpf(0.0, 0.16, e)
		_torso.rotation.x = lerpf(-0.15, 0.34, e)
		_torso.rotation.z = 0.0
		# 頭側躺，臉朝著路面外側
		_head.rotation.x = lerpf(0.0, 0.55, e)
		_head.rotation.z = lerpf(0.0, 0.85, e)
		# 雙手往前伸直貼地
		_arm_l.rotation.x = lerpf(0.9, 1.5, e)
		_arm_r.rotation.x = lerpf(0.75, 1.4, e)
		_arm_l.rotation.z = lerpf(-0.60, -0.18, e)
		_arm_r.rotation.z = lerpf(0.60, 0.18, e)
		_forearm_l.rotation.x = lerpf(-0.7, -0.25, e)
		_forearm_r.rotation.x = lerpf(-0.7, -0.25, e)
		# 腿往後伸直
		_leg_l.rotation.x = lerpf(-0.55, -0.42, e)
		_leg_r.rotation.x = lerpf(-0.35, -0.30, e)
		_shin_l.rotation.x = lerpf(0.6, 0.30, e)
		_shin_r.rotation.x = lerpf(0.45, 0.25, e)
		_scarf.rotation.x = lerpf(-1.1, -0.35, e)

		# 趴在地上之後只剩很輕的呼吸起伏
		var breath := sin(_fling_t * 5.0) * 0.022
		_hips.position.y += breath
		_hips.rotation.z = breath * 0.6

	_animate_tail(delta)
	_shadow.scale = Vector3.ONE * (1.0 - 0.15 * clampf(_fling_t / 0.6, 0.0, 1.0))
	# 落地之後才做接地修正：空中的時候對齊到地面會看起來像被拉回來
	if _fling_t >= FLIGHT:
		var gs := clampf(delta * 12.0, 0.0, 1.0)
		if _fling_t >= FLIGHT + 0.34:
			gs = 1.0
		_settle_ground(gs)


## 體力用盡的跪坐動畫。
##
## 分三段：前 0.35 秒往前撲（失衡），接著重心一路往下掉到跪坐，
## 最後 0.4 秒低頭喘氣。整段約 1.4 秒，之後停在跪姿不動。
## 接地修正。
##
## 問題：摔倒的姿勢是手動拼出來的旋轉角度，所以沒有任何機制保證身體
## 貼在地面上 —— 實測趴地姿勢會沉到路面下 0.83 公尺，一半看不見。
## 與其靠肉眼調角度，這裡每幀量一次所有可見網格的世界座標最低點，
## 再把整個 rig 往上（或往下）補到剛好貼地。
## 姿勢改變時（例如從空中落到地面）會自動重新對齊。
const GROUND_Y := 0.03

var _scan_low := 0.0
var _ground_fix := 0.0


func _scan_lowest(r: Node) -> void:
	if r is MeshInstance3D:
		var mi := r as MeshInstance3D
		if mi.visible and mi.mesh != null:
			var bb := mi.global_transform * mi.get_aabb()
			_scan_low = minf(_scan_low, bb.position.y)
	for c in r.get_children():
		_scan_lowest(c)


## 貼到地面。strength < 1 用於漸進對齊，避免突然跳動。
func _settle_ground(strength := 1.0) -> void:
	_scan_low = INF
	_scan_lowest(_rig)
	# 量到的是世界座標，但補的是 _rig 的本地位移。
	# 角色整體有 1.16 倍縮放，兩者差一個倍率，不除掉的話永遠補不滿。
	_ground_fix += (GROUND_Y - _scan_low) / maxf(scale.y, 0.001) * clampf(strength, 0.0, 1.0)
	_rig.position.y = _ground_fix


func _process_collapse(delta: float) -> void:
	if _collapse_flung:
		_process_fling(delta)
		return
	_collapse = minf(1.0, _collapse + delta / 1.4)
	var t := _collapse
	var stumble := clampf(t / 0.28, 0.0, 1.0)
	var sink := clampf((t - 0.22) / 0.55, 0.0, 1.0)
	var ease := 1.0 - pow(1.0 - sink, 3.0)
	var breathe := sin(_collapse * 7.0) * 0.03 * clampf((t - 0.7) / 0.3, 0.0, 1.0)

	# 撲出去之後重心墜到地面，最後跪著
	_rig.rotation.x = lerpf(0.0, 0.55, stumble) * (1.0 - ease) - ease * 0.10
	_rig.rotation.z = _bank + lerpf(0.0, -0.22, stumble) * (1.0 - ease)
	position.x = _lane

	_hips.position.y = lerpf(HIP_Y, 0.34, ease) + breathe
	_hips.position.z = lerpf(0.0, -0.20, ease)
	_hips.rotation.x = lerpf(0.0, 0.34, ease)
	# 上身往前折、頭低下去：這兩個角度是「撐不住」的關鍵
	_torso.rotation.x = lerpf(-0.2, 0.88, ease)
	_torso.rotation.z = breathe * 2.0
	_torso.rotation.y = 0.0
	_head.rotation.x = lerpf(0.0, 0.78, clampf((t - 0.55) / 0.45, 0.0, 1.0))

	# 雙手撐在身前地上。
	# 之前把手臂往外張（像在保持平衡），讀起來是絆倒而不是放棄。
	_arm_l.rotation.x = lerpf(0.0, 0.72, ease)
	_arm_r.rotation.x = lerpf(0.0, 0.72, ease)
	_arm_l.rotation.z = -0.10 - 0.10 * ease
	_arm_r.rotation.z = 0.10 + 0.10 * ease
	_forearm_l.rotation.x = -1.15 * ease
	_forearm_r.rotation.x = -1.15 * ease

	# 大腿跪地、小腿向後收到腳背貼地
	_leg_l.rotation.x = lerpf(0.0, 1.52, ease)
	_leg_r.rotation.x = lerpf(0.0, 1.28, ease)
	_shin_l.rotation.x = lerpf(0.0, -2.25, ease)
	_shin_r.rotation.x = lerpf(0.0, -2.05, ease)

	_scarf.rotation.x = -0.9 * ease + sin(t * 4.0) * 0.05 * breathe
	# 姿勢靜止後直接吸附到位，避免比例控制留下幾公分的殘差
	var gs := clampf(delta * 14.0, 0.0, 1.0)
	if _collapse >= 0.995:
		gs = 1.0
	_settle_ground(gs)
	_animate_tail(delta)
	_shadow.scale = Vector3.ONE * (1.0 - 0.2 * ease)


func _animate_tail(delta: float) -> void:
	var drive := -sin(_phase) * 0.55 - speed01 * 0.25
	for i in _ponytail.size():
		var target := drive * (0.5 + i * 0.35) - _bank * 1.4
		var k := 26.0 - i * 4.0
		var damping := 7.5
		_tail_vel[i] += (target - _tail_spring[i]) * k * delta
		_tail_vel[i] -= _tail_vel[i] * clampf(damping * delta, 0.0, 1.0)
		_tail_spring[i] += _tail_vel[i] * delta
		var seg := _ponytail[i]
		seg.rotation.x = _tail_spring[i] * 0.75
		seg.rotation.z = sin(_phase * 1.3 + i) * 0.22 * (0.4 + speed01)
