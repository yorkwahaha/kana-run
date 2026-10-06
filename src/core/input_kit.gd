extends Node
## InputKit — 在執行期建立 InputMap，並統一處理觸控手勢。
##
## 啟動時把「物理按鍵 + 螢幕按鈕」都映射到同一組語意動作，
## 讓玩法程式碼完全不必分辨輸入來源。

const ACTIONS := {
	&"lane_left": {
		"keys": [KEY_A, KEY_LEFT],
		"joy": [JOY_BUTTON_DPAD_LEFT],
		"axis": {JOY_AXIS_LEFT_X: -1.0},
	},
	&"lane_right": {
		"keys": [KEY_D, KEY_RIGHT],
		"joy": [JOY_BUTTON_DPAD_RIGHT],
		"axis": {JOY_AXIS_LEFT_X: 1.0},
	},
	&"dodge": {
		"keys": [KEY_S, KEY_DOWN, KEY_X],
		"joy": [JOY_BUTTON_DPAD_DOWN],
		"axis": {JOY_AXIS_LEFT_Y: 1.0},
	},
	&"pick_1": {
		"keys": [KEY_1, KEY_KP_1],
		"joy": [],
		"axis": {},
	},
	&"pick_2": {
		"keys": [KEY_2, KEY_KP_2],
		"joy": [],
		"axis": {},
	},
	&"pick_3": {
		"keys": [KEY_3, KEY_KP_3],
		"joy": [],
		"axis": {},
	},
	&"confirm": {
		"keys": [KEY_SPACE, KEY_ENTER, KEY_KP_ENTER, KEY_Z],
		"joy": [JOY_BUTTON_A],
		"axis": {JOY_AXIS_TRIGGER_RIGHT: 1.0},
	},
	&"pause": {
		"keys": [KEY_ESCAPE, KEY_P],
		"joy": [JOY_BUTTON_START],
		"axis": {},
	},
	&"restart": {
		"keys": [KEY_R],
		"joy": [JOY_BUTTON_BACK],
		"axis": {},
	},
	&"debug_toggle": {
		"keys": [KEY_F3],
		"joy": [],
		"axis": {},
	},
}

const SWIPE_MIN_PX := 42.0
const TAP_MAX_MS := 260.0
const TAP_MAX_SLOP := 26.0

## 每幀由 Main 呼叫 begin_frame() 歸零，再讀取這些欄位。
var swipe_dir := 0
var tapped := false
var tap_position := Vector2.ZERO
var dodge_pressed := false

# Godot 的順序是 _input → _process。如果 begin_frame() 直接把上面這幾個
# 欄位清零，_input 在同一幀設好的手勢會在 Main 讀到之前就被抹掉，
# 結果是「下滑完全沒反應、點擊也沒反應」。
# 所以分成兩層：_input 只寫入 _p_*，begin_frame() 再把它們搬到上面那組欄位。
var _p_swipe := 0
var _p_tapped := false
var _p_tap_pos := Vector2.ZERO
var _p_dodge := false
var _p_tapped_swiped_down := false

## 下滑的「輕點」變體：平板上很常見把下滑手勢結束得很快，
## 只累積到一點點位移就被判定成點擊。/gameplay 用它避免同一次
## 手勢被當成「點擊 + 閃避」而觸發兩個動作。
var tapped_swiped_down := false

var _touch_start := Vector2.ZERO
var _touch_time := 0
var _touch_active := false
var _consumed := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_actions()


func _build_actions() -> void:
	for action in ACTIONS.keys():
		if not InputMap.has_action(action):
			InputMap.add_action(action, 0.2)
		var spec: Dictionary = ACTIONS[action]
		for key in spec.get("keys", []):
			var ev := InputEventKey.new()
			ev.physical_keycode = key
			InputMap.action_add_event(action, ev)
		for btn in spec.get("joy", []):
			var jb := InputEventJoypadButton.new()
			jb.button_index = btn
			InputMap.action_add_event(action, jb)
		for axis in spec.get("axis", {}).keys():
			var jm := InputEventJoypadMotion.new()
			jm.axis = axis
			jm.axis_value = spec["axis"][axis]
			InputMap.action_add_event(action, jm)


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.pressed:
			# 點在按鈕上的那一下交給按鈕。否則右上角暫停、下方「中」
			# 會同時被當成點擊換道。
			if _top_control(touch.position) is BaseButton:
				_touch_active = false
				_consumed = true
				return
			_touch_active = true
			_consumed = false
			_touch_start = touch.position
			_touch_time = Time.get_ticks_msec()
		elif _touch_active and not _consumed:
			var dt := Time.get_ticks_msec() - _touch_time
			var travel := touch.position - _touch_start
			if dt <= TAP_MAX_MS and travel.length() <= TAP_MAX_SLOP:
				_p_tapped = true
				_p_tap_pos = touch.position
				# 螢幕座標的 y 往下遞增，所以「往下滑」是 travel.y 為正。
				# 這種點下去的位置明顯偏下時，仍然視為一次下滑意圖，
				# 同一個手勢就不會又點擊又閃避，音效只響一次。
				if travel.y > SWIPE_MIN_PX * 0.55:
					_p_tapped_swiped_down = true
			_touch_active = false
	elif event is InputEventScreenDrag and _touch_active and not _consumed:
		var drag := event as InputEventScreenDrag
		var d := drag.position - _touch_start
		if absf(d.x) >= absf(d.y):
			if absf(d.x) >= SWIPE_MIN_PX:
				_p_swipe = -1 if d.x < 0.0 else 1
				_consumed = true
		elif d.y >= SWIPE_MIN_PX:
			_p_dodge = true
			_consumed = true


## 把 _input 期間收集到的手勢交給這一幀的 gameplay 邏輯。
## 不是清零，而是「把待處理值搬進本幀欄位」。
func begin_frame() -> void:
	swipe_dir = _p_swipe
	tapped = _p_tapped
	tap_position = _p_tap_pos
	dodge_pressed = _p_dodge
	tapped_swiped_down = _p_tapped_swiped_down
	_p_swipe = 0
	_p_tapped = false
	_p_dodge = false
	_p_tapped_swiped_down = false


## 這一點最上面、會收下點擊的控制項。IGNORE 的跳過。
func _top_control(pos: Vector2) -> Control:
	var tree := get_tree()
	if tree == null:
		return null
	return _top_control_at(tree.root, pos)


func _top_control_at(node: Node, pos: Vector2) -> Control:
	if node is CanvasItem and not (node as CanvasItem).is_visible_in_tree():
		return null
	var kids := node.get_children()
	for i in range(kids.size() - 1, -1, -1):
		var hit := _top_control_at(kids[i], pos)
		if hit != null:
			return hit
	if node is Control:
		var c := node as Control
		if c.mouse_filter != Control.MOUSE_FILTER_IGNORE and c.get_global_rect().has_point(pos):
			return c
	return null
