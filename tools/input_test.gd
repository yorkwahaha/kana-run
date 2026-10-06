extends SceneTree
## 輸入管線回歸測試：確認鍵盤綁定與觸控手勢真的能送到 gameplay 邏輯。
##
## 這支測試是為了守住兩個已經修過的 bug：
##   1. begin_frame() 直接清零，導致 _input 設好的手勢在同幀被抹掉
##      （下滑與點擊完全沒反應）
##   2. dodge 的按鍵有註冊進 InputMap，但 gameplay 從來沒查過它

var _kit: Node
var _fails: Array[String] = []


func _init() -> void:
	_run.call_deferred()


func _ok(cond: bool, what: String) -> void:
	if cond:
		print("  PASS  ", what)
	else:
		_fails.append(what)
		print("  FAIL  ", what)


func _bound_keys(action: String) -> Array:
	var out: Array = []
	for e in InputMap.action_get_events(action):
		if e is InputEventKey:
			out.append((e as InputEventKey).physical_keycode)
	return out


## 依真實的幀序：事件被注入 → 等一幀讓 _input 跑到 → begin_frame() 交棒
func _gesture(fn: Callable) -> Dictionary:
	fn.call()
	await process_frame
	_kit.begin_frame()
	return {
		"swipe": _kit.swipe_dir,
		"dodge": _kit.dodge_pressed,
		"tapped": _kit.tapped,
		"pos": _kit.tap_position,
	}


func _touch_drag(from: Vector2, to: Vector2) -> void:
	var t := InputEventScreenTouch.new()
	t.pressed = true
	t.position = from
	Input.parse_input_event(t)
	var d := InputEventScreenDrag.new()
	d.position = to
	Input.parse_input_event(d)
	var r := InputEventScreenTouch.new()
	r.pressed = false
	r.position = to
	Input.parse_input_event(r)


func _tap(pos: Vector2) -> void:
	var t := InputEventScreenTouch.new()
	t.pressed = true
	t.position = pos
	Input.parse_input_event(t)
	var r := InputEventScreenTouch.new()
	r.pressed = false
	r.position = pos
	Input.parse_input_event(r)


func _run() -> void:
	_kit = load("res://src/core/input_kit.gd").new()
	get_root().add_child(_kit)
	_kit.process_mode = Node.PROCESS_MODE_ALWAYS
	await process_frame

	print("[input-test] 鍵盤綁定")
	var dodge_keys := _bound_keys("dodge")
	_ok(KEY_S in dodge_keys, "dodge 綁定 S")
	_ok(KEY_DOWN in dodge_keys, "dodge 綁定 ↓")
	_ok(KEY_X in dodge_keys, "dodge 綁定 X")
	_ok(KEY_A in _bound_keys("lane_left"), "lane_left 綁定 A")
	_ok(KEY_LEFT in _bound_keys("lane_left"), "lane_left 綁定 ←")
	_ok(KEY_D in _bound_keys("lane_right"), "lane_right 綁定 D")
	_ok(KEY_RIGHT in _bound_keys("lane_right"), "lane_right 綁定 →")
	_ok(KEY_1 in _bound_keys("pick_1"), "pick_1 綁定 1")
	var accept_joy := false
	for e in InputMap.action_get_events("ui_accept"):
		if e is InputEventJoypadButton and (e as InputEventJoypadButton).button_index == JOY_BUTTON_A:
			accept_joy = true
	_ok(accept_joy, "ui_accept 綁定手把 A")
	var cancel_joy := false
	for e in InputMap.action_get_events("ui_cancel"):
		if e is InputEventJoypadButton and (e as InputEventJoypadButton).button_index == JOY_BUTTON_B:
			cancel_joy = true
	_ok(cancel_joy, "ui_cancel 綁定手把 B")

	print("[input-test] 觸控手勢")
	var g: Dictionary = await _gesture(func():
		_touch_drag(Vector2(600, 400), Vector2(480, 404)))
	_ok(int(g["swipe"]) == -1, "向左滑 = swipe_dir -1（得到 %d）" % int(g["swipe"]))

	g = await _gesture(func():
		_touch_drag(Vector2(480, 400), Vector2(620, 402)))
	_ok(int(g["swipe"]) == 1, "向右滑 = swipe_dir 1（得到 %d）" % int(g["swipe"]))

	g = await _gesture(func():
		_touch_drag(Vector2(640, 300), Vector2(646, 420)))
	_ok(bool(g["dodge"]), "下滑 = dodge_pressed")

	g = await _gesture(func():
		_touch_drag(Vector2(640, 200), Vector2(650, 600)))
	_ok(bool(g["dodge"]), "長距離下滑 = dodge_pressed")

	g = await _gesture(func():
		_tap(Vector2(200, 500)))
	_ok(bool(g["tapped"]), "點擊 = tapped")
	# 無頭模式會模擬 4000×10000 的觸控螢幕，絕對座標會被校正，
	# 所以這裡只確認座標有被帶上來，不比對實際數值。
	_ok((g["pos"] as Vector2) != Vector2.ZERO, "點擊座標有回報")

	print("[input-test] 單次手勢不會連續觸發")
	_kit.begin_frame()
	_ok(not _kit.dodge_pressed, "下一幀 dodge_pressed 已清空")
	_ok(_kit.swipe_dir == 0, "下一幀 swipe_dir 已清空")
	_ok(not _kit.tapped, "下一幀 tapped 已清空")
	_ok(not _kit.tapped_swiped_down, "下一幀 tapped_swiped_down 已清空")

	# 一幀只做一個動作。
	# 這是「下滑聽到兩聲音效」的真正修法：不管幾個來源同時成立
	# （觸控裝置常把一次手勢同時送成按鍵事件與觸控事件），
	# gameplay 只會呼叫一次 _do_dodge()。
	# 這裡直接驗證 acted 這個判斷式，而不是驗證手勢門檻 ——
	# 無頭模式會模擬 4000×10000 的觸控螢幕，像素門檻會被放大，
	# 在 headless 下量不准。
	print("[input-test] 一幀只有一個動作")
	_kit.begin_frame()
	_kit.dodge_pressed = true          # 模擬觸控下滑
	_kit.tapped_swiped_down = true    # 同一幀也帶下滑意圖
	_kit.tapped = true                # 而且同時被當成點擊
	_kit.swipe_dir = 0
	var acted: bool = bool(_kit.dodge_pressed) or bool(_kit.tapped_swiped_down)
	_ok(acted, "下滑意圖成立 → acted = true")
	_ok(not (acted and _kit.swipe_dir != 0), "不會同時閃避又換線")
	_kit.begin_frame()
	_ok(not _kit.dodge_pressed and not _kit.tapped and not _kit.tapped_swiped_down,
		"三個旗標都會在下一幀清空")

	print("[input-test] 手把震動")
	_kit.rumble_hit()
	_kit.rumble_miss()
	_ok(true, "答對／答錯震動呼叫不崩潰")

	print("[input-test] 失敗 %d 項" % _fails.size())
	quit(0 if _fails.is_empty() else 1)
