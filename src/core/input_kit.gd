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
	_ensure_menu_joy()
	if OS.has_feature("web"):
		_install_web_rumble()


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


## 答對是短震，答錯是長而重的震。
## 藍牙馬達要轉起來需要比較久，太短會完全感覺不到。
## 強度跟著設定裡的「畫面震動」。關到 0 就不震。
func rumble_hit() -> void:
	_rumble(0.4, 0.85, 0.22)


func rumble_miss() -> void:
	_rumble(1.0, 1.0, 0.48)


func _rumble(strong: float, weak: float, seconds: float) -> void:
	var scale := float(SaveGame.get_setting("screen_shake", 1.0))
	if scale <= 0.01:
		return
	strong = clampf(strong * scale, 0.0, 1.0)
	weak = clampf(weak * scale, 0.0, 1.0)
	for id in Input.get_connected_joypads():
		Input.start_joy_vibration(id, weak, strong, seconds)
	# 網頁版的 start_joy_vibration 是空的（Godot #96985）。
	# 平板瀏覽器要另外打 Gamepad Haptics。沒有馬達的瀏覽器會自己跳過。
	if OS.has_feature("web"):
		_web_rumble(weak, strong, int(seconds * 1000.0))


func _install_web_rumble() -> void:
	var js := JavaScriptBridge
	if js == null:
		return
	# Chrome 的 Gamepad Haptics 對藍牙 Xbox 常常沒有 vibrationActuator。
	# 那種情況改走 WebHID，直接把 Xbox 的震動封包送出去。
	# 第一次點畫面時才會跳出「選擇裝置」，而且只問一次。
	js.eval("""
if (!window.__kanaRumble) {
  window.__kanaRumGen = 0;
  window.__kanaHidAsked = false;
  function motors(strong, weak) {
    var s = Math.max(0, Math.min(255, Math.round(strong * 255)));
    var w = Math.max(0, Math.min(255, Math.round(weak * 255)));
    return new Uint8Array([0x0F, 0, 0, s, w, 0xFF, 0, 0]);
  }
  function sendHid(list, data) {
    list.forEach(function(d) {
      if (d.vendorId !== 0x045e) return;
      var opened = d.opened ? Promise.resolve() : d.open();
      opened.then(function() { return d.sendReport(0x03, data); }).catch(function(e) {
        if (!window.__kanaHidErr) { window.__kanaHidErr = 1; console.warn('[kana-rumble] hid', e); }
      });
    });
  }
  function padNeedsHid() {
    var pads = navigator.getGamepads ? navigator.getGamepads() : [];
    var any = false;
    for (var i = 0; i < pads.length; i++) {
      var p = pads[i];
      if (!p) continue;
      any = true;
      var a = p.vibrationActuator || (p.hapticActuators && p.hapticActuators[0]);
      if (a && a.playEffect) return false;
    }
    return any;
  }
  function askHid() {
    if (!navigator.hid || window.__kanaHidAsked || !padNeedsHid()) return;
    window.__kanaHidAsked = true;
    navigator.hid.requestDevice({filters:[{vendorId:0x045e}]}).catch(function(){});
  }
  window.addEventListener('pointerdown', askHid);
  window.addEventListener('keydown', askHid);
  window.__kanaRumble = function(weak, strong, ms) {
    var gen = ++window.__kanaRumGen;
    var played = 0;
    var pads = navigator.getGamepads ? navigator.getGamepads() : [];
    for (var i = 0; i < pads.length; i++) {
      var p = pads[i];
      if (!p) continue;
      var a = p.vibrationActuator || (p.hapticActuators && p.hapticActuators[0]);
      if (!a || !a.playEffect) continue;
      var type = (a.type && a.type !== 'vibration') ? a.type : 'dual-rumble';
      try {
        var ret = a.playEffect(type, {startDelay:0, duration:ms, weakMagnitude:weak, strongMagnitude:strong});
        if (ret && ret.then) ret.then(function(){}, function(e) {
          if (!window.__kanaActErr) { window.__kanaActErr = 1; console.warn('[kana-rumble] actuator', e && e.name, e && e.message); }
        });
        played++;
      } catch (e) {
        if (!window.__kanaActErr) { window.__kanaActErr = 1; console.warn('[kana-rumble]', e); }
      }
    }
    if (played || !navigator.hid) {
      if (!window.__kanaRumbleLogged) { window.__kanaRumbleLogged = 1; console.log('[kana-rumble] actuator', played); }
      return;
    }
    navigator.hid.getDevices().then(function(devs) {
      var xbox = [];
      for (var i = 0; i < devs.length; i++) if (devs[i].vendorId === 0x045e) xbox.push(devs[i]);
      if (!xbox.length) {
        if (!window.__kanaRumbleLogged) { window.__kanaRumbleLogged = 1; console.log('[kana-rumble] no actuator and no hid device'); }
        return;
      }
      sendHid(xbox, motors(strong, weak));
      setTimeout(function() {
        if (window.__kanaRumGen !== gen) return;
        sendHid(xbox, motors(0, 0));
      }, ms);
    });
  };
}
""", true)


func _web_rumble(weak: float, strong: float, ms: int) -> void:
	var js := JavaScriptBridge
	if js == null:
		return
	js.eval("if(window.__kanaRumble)window.__kanaRumble(%s,%s,%d);" % [str(weak), str(strong), ms], true)


func _ensure_menu_joy() -> void:
	_add_joy_button(&"ui_accept", JOY_BUTTON_A)
	_add_joy_button(&"ui_cancel", JOY_BUTTON_B)
	_add_joy_button(&"ui_up", JOY_BUTTON_DPAD_UP)
	_add_joy_button(&"ui_down", JOY_BUTTON_DPAD_DOWN)
	_add_joy_button(&"ui_left", JOY_BUTTON_DPAD_LEFT)
	_add_joy_button(&"ui_right", JOY_BUTTON_DPAD_RIGHT)
	_add_joy_axis(&"ui_up", JOY_AXIS_LEFT_Y, -1.0)
	_add_joy_axis(&"ui_down", JOY_AXIS_LEFT_Y, 1.0)
	_add_joy_axis(&"ui_left", JOY_AXIS_LEFT_X, -1.0)
	_add_joy_axis(&"ui_right", JOY_AXIS_LEFT_X, 1.0)


func _add_joy_button(action: StringName, button: JoyButton) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	for ev in InputMap.action_get_events(action):
		if ev is InputEventJoypadButton and (ev as InputEventJoypadButton).button_index == button:
			return
	var e := InputEventJoypadButton.new()
	e.button_index = button
	InputMap.action_add_event(action, e)


func _add_joy_axis(action: StringName, axis: JoyAxis, value: float) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	for ev in InputMap.action_get_events(action):
		if ev is InputEventJoypadMotion and (ev as InputEventJoypadMotion).axis == axis \
				and is_equal_approx((ev as InputEventJoypadMotion).axis_value, value):
			return
	var e := InputEventJoypadMotion.new()
	e.axis = axis
	e.axis_value = value
	InputMap.action_add_event(action, e)
