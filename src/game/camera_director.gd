extends Camera3D
## CameraDirector — 攝影機的「導演」職責。
##
## 負責：跟隨跑者、依速度推拉 FOV、撞擊時的震動與推進、
## 以及答對時的短暫焦點脈動。全部用 delta 推導，60/120Hz 一致。

## 鏡頭往前拉一點：跑者原本只有 ~90px 高，動作細節全部看不清，
## 整個人看起來像一個小色塊。拉近後近景更有壓迫感，
## 遠方石碑在畫面上也變大，碑面假名更容易讀。
const BASE_POS := Vector3(0, 4.15, 10.0)
const BASE_LOOK := Vector3(0, 2.00, -13.5)
const BASE_FOV := 62.0

## 倒地時的鏡頭位：壓低並拉近到跑者身上
const DOLLY_POS := Vector3(0, 1.95, 3.9)
const DOLLY_LOOK := Vector3(0, 0.55, -2.0)

var _dolly := 0.0
var _dolly_target := 0.0

var speed01 := 0.0
var reduce_motion := 0.0

## 撞飛時鏡頭往前追的位移與抬升。非撞飛時恆為 0，
## 靠 follow_flight() 插值回 0，不會突然跳回去。
var _track_z := 0.0
var _track_y := 0.0

var _shake := 0.0
var _shake_decay := 5.0
var _kick := Vector3.ZERO
var _focus := 0.0
var _lane := 0.0
var _look := Vector3.ZERO
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	fov = BASE_FOV
	near = 0.08
	far = 900.0
	_look = BASE_LOOK
	position = BASE_POS
	look_at(_look, Vector3.UP)


func reset() -> void:
	_lane = 0.0
	speed01 = 0.0
	_shake = 0.0
	_kick = Vector3.ZERO
	_focus = 0.0
	_dolly = 0.0
	_dolly_target = 0.0
	_track_z = 0.0
	_track_y = 0.0
	fov = BASE_FOV
	position = BASE_POS
	_look = BASE_LOOK
	look_at(_look, Vector3.UP)


func shake(amount: float, decay := 5.0) -> void:
	_shake = maxf(_shake, amount * (1.0 - reduce_motion * 0.85))
	_shake_decay = decay


func punch(amount: float) -> void:
	_kick += Vector3(0, 0, amount)


func pulse(amount := 1.0) -> void:
	_focus = maxf(_focus, amount)


func follow(runner_x: float, delta: float) -> void:
	_lane = lerpf(_lane, runner_x, clampf(delta * 9.0, 0.0, 1.0))
	_dolly = lerpf(_dolly, _dolly_target, clampf(delta * 3.2, 0.0, 1.0))


## 撞飛時讓鏡頭跟著往前追一段。
##
## 鏡頭停在原位時，角色往前飛 5.6 公尺會讓距離從 10 公尺變成 15.6 公尺，
## 投影縮小三分之一 —— 讀起來像「跑掉了」而不是「被撞飛」。
## 追到 8 成、落地位移收斂回 0，落地後自然回到原本的鏡位。
func follow_flight(runner_z: float, runner_y: float, delta: float) -> void:
	_track_z = lerpf(_track_z, clampf(runner_z, -6.0, 0.0), clampf(delta * 5.0, 0.0, 1.0))
	_track_y = lerpf(_track_y, clampf(runner_y, 0.0, 1.4), clampf(delta * 7.0, 0.0, 1.0))


## 1 = 推近到倒地特寫，0 = 正常跟隨
func set_dolly(on: bool) -> void:
	_dolly_target = 1.0 if on else 0.0


func _process(delta: float) -> void:
	# 衰減
	_shake = maxf(0.0, _shake - _shake * clampf(delta * _shake_decay, 0.0, 1.0) - delta * 0.04)
	_kick = _kick.lerp(Vector3.ZERO, clampf(delta * 9.0, 0.0, 1.0))
	_focus = maxf(0.0, _focus - delta * 2.4)

	var sh := Vector3(
		_rng.randf_range(-1.0, 1.0),
		_rng.randf_range(-1.0, 1.0),
		_rng.randf_range(-0.4, 0.4)
	) * _shake * 0.30

	# 撞飛時鏡頭跟著往前追，否則角色會縮成一個小點
	var track := Vector3(0, _track_y, _track_z)
	var target := BASE_POS + Vector3(_lane * 0.42, 0, 0) + track + sh + _kick
	# 倒地結算時推近鏡頭：趴在地上的角色投影很小，
	# 不推近的話玩家根本看不出她是怎麼倒的。
	target = target.lerp(DOLLY_POS, clampf(_dolly, 0.0, 1.0))
	position = position.lerp(target, clampf(delta * 18.0, 0.0, 1.0))

	var look := BASE_LOOK + Vector3(_lane * 0.22, _track_y * 0.6, _track_z * 0.85)
	look = look.lerp(DOLLY_LOOK, clampf(_dolly, 0.0, 1.0))
	_look = _look.lerp(look, clampf(delta * 12.0, 0.0, 1.0))
	look_at(_look + sh * 0.4, Vector3.UP)

	# 速度感：FOV 推近 + 輕微滾轉
	fov = lerpf(fov, BASE_FOV + speed01 * 15.0, clampf(delta * 3.2, 0.0, 1.0))
	rotation.z = lerpf(rotation.z, -_lane * 0.018, clampf(delta * 6.0, 0.0, 1.0))


func focus() -> float:
	return _focus
