extends SceneTree
## 驗證觸控面板的版面。
##
## 為什麼不用截圖：桌機沒有觸控螢幕，面板預設隱藏，
## 截圖只會拍到空畫面，看不出按鈕位置對不對。
## 直接讀每顆按鈕在螢幕上的實際矩形，精確又不用開視窗。

func _init() -> void:
	_run.call_deferred()


func _find_button(node: Node, text: String) -> Button:
	for c in node.get_children():
		if c is Button and (c as Button).text == text:
			return c as Button
		var found := _find_button(c, text)
		if found != null:
			return found
	return null


func _run() -> void:
	var hud_script = load("res://src/ui/hud.gd")
	var hud = hud_script.new()
	root.add_child(hud)
	var pad: Control = hud.get("_touch_pad")
	pad.visible = true

	# headless 的 Window 不會自己跑佈局，Control 的 size 會一直是 0。
	# 直接把尺寸指定給兩個 Control，再叫它重算版面。
	root.content_scale_size = Vector2i(1280, 720)
	root.size = Vector2i(1280, 720)
	hud.size = Vector2(1280, 720)
	pad.size = Vector2(1280, 720)
	await process_frame
	hud.notification(Control.NOTIFICATION_RESIZED)
	await process_frame

	var vp := Vector2(1280, 720)
	print("[touch] 視窗 %dx%d  pad=%s" % [int(vp.x), int(vp.y), str(pad.size)])

	var names := ["左", "閃", "中", "右"]
	var fails := 0
	var mid_x := vp.x * 0.5

	for b in pad.get_children():
		if not (b is Button):
			continue
		var btn := b as Button
		var r := btn.get_global_rect()
		var cx := r.position.x + r.size.x * 0.5
		var side := "左" if cx < mid_x else "右"
		print("[touch] %-3s 中心=(%4d,%4d) 尺寸=%dx%d  → %s側" % [
			btn.text, int(cx), int(r.position.y + r.size.y * 0.5),
			int(r.size.x), int(r.size.y), side])

		# 1. 四顆都要在畫面內
		if r.position.x < 0 or r.position.y < 0 \
				or r.position.x + r.size.x > vp.x or r.position.y + r.size.y > vp.y:
			print("   ★ 超出畫面")
			fails += 1
		# 2. 不能壓到畫面正中央（跑者所在）
		if r.position.x < mid_x and r.position.x + r.size.x > mid_x:
			print("   ★ 跨到畫面中央，會遮住跑者")
			fails += 1
		# 3. 必須貼近底部（拇指自然落點）
		if r.position.y + r.size.y < vp.y - 220.0:
			print("   ★ 離底部太遠，拇指搆不到")
			fails += 1
		# 4. 按鈕不能太小（手機手指）
		if r.size.x < 70 or r.size.y < 55:
			print("   ★ 太小，手指按不到")
			fails += 1

	# 5. 左／中／右是「絕對跑道」0/1/2，不是相對位移 -1/0/1。
	# 之前這裡沒有測語意，導致手機的左與中都送到 lane 0、lane 2 永遠選不到。
	var lanes: Array[int] = []
	hud.lane_requested.connect(func(lane: int): lanes.append(lane))
	var lane_buttons := [pad.get_child(0), pad.get_child(2), pad.get_child(3)]
	for b in lane_buttons:
		(b as Button).pressed.emit()
		await process_frame
	if lanes != [0, 1, 2]:
		print("   ★ 跑道按鈕訊號錯誤：%s（預期 [0, 1, 2]）" % str(lanes))
		fails += 1
	else:
		print("[touch] 跑道訊號  左/中/右 → 0/1/2")

	# 6. 遊戲中必須有可點的暫停鈕，不能只靠鍵盤 Esc。
	var pause_button := _find_button(hud, "暫停")
	var pause_events: Array[bool] = []
	hud.pause_requested.connect(func(): pause_events.append(true))
	if pause_button == null:
		print("   ★ 找不到暫停按鈕")
		fails += 1
	else:
		pause_button.pressed.emit()
		await process_frame
		if pause_events.is_empty():
			print("   ★ 暫停按鈕沒有送出 pause_requested")
			fails += 1
		else:
			print("[touch] 暫停按鈕可用")

	# 7. 遊戲中的暫停鈕必須真的收得到點擊。
	# Overlays 蓋在 HUD 上面。它若是全螢幕 STOP，點暫停只會打到那層空殼，
	# 按鈕的 pressed 永遠不會來。鍵盤 Esc 走的是另一條路，所以只有觸控會壞。
	var ui_script = load("res://src/ui/overlays.gd")
	var ui = ui_script.new()
	var layer := CanvasLayer.new()
	root.add_child(layer)
	hud.reparent(layer)
	layer.add_child(ui)
	hud.size = Vector2(1280, 720)
	ui.size = Vector2(1280, 720)
	ui.hide_all()
	await process_frame
	hud.notification(Control.NOTIFICATION_RESIZED)
	await process_frame

	if ui.mouse_filter != Control.MOUSE_FILTER_IGNORE:
		print("   ★ 介面根節點會吃掉暫停鈕的觸控")
		fails += 1
	else:
		print("[touch] 介面根節點不擋觸控")

	if pause_button != null:
		var pause_rect := pause_button.get_global_rect()
		var pause_at := pause_rect.position + pause_rect.size * 0.5
		var picked := _pick(layer, pause_at)
		if picked != pause_button:
			var who := "沒有控制項"
			if picked != null:
				who = picked.get_class()
				if picked is Button:
					who += "「%s」" % (picked as Button).text
			print("   ★ 暫停鈕中心點到的是 %s" % who)
			fails += 1
		else:
			print("[touch] 暫停鈕中心可點")

	ui.show_title()
	await process_frame
	for label in ["開始", "設定", "學習儀表板"]:
		var entry := _find_button(ui, label)
		if entry == null:
			print("   ★ 首頁缺少「%s」" % label)
			fails += 1
		elif not (entry.get_theme_stylebox("normal") is StyleBoxEmpty):
			print("   ★ 「%s」還有底框" % label)
			fails += 1
	if fails == 0:
		print("[touch] 首頁三個入口只有文字")

	ui.show_brief()
	await process_frame
	if _find_button(ui, "90 秒驟死") == null:
		print("   ★ 選關沒有 90 秒驟死")
		fails += 1
	if _find_button(ui, "玩法說明") == null:
		print("   ★ 選關沒有玩法說明")
		fails += 1
	else:
		(_find_button(ui, "玩法說明") as Button).pressed.emit()
		await process_frame
		if ui.get("_current") != ui.Page.HELP:
			print("   ★ 玩法說明沒有打開")
			fails += 1
		else:
			print("[touch] 選關含驟死與玩法說明")

	print("[touch] 失敗 %d 項" % fails)
	quit(0 if fails == 0 else 1)


## 由上往下找第一個會收下點擊的控制項。近似 Godot 的 GUI picking。
func _pick(node: Node, pos: Vector2) -> Control:
	if node is CanvasItem and not (node as CanvasItem).is_visible_in_tree():
		return null
	var kids := node.get_children()
	for i in range(kids.size() - 1, -1, -1):
		var hit := _pick(kids[i], pos)
		if hit != null:
			return hit
	if node is Control:
		var c := node as Control
		if c.mouse_filter != Control.MOUSE_FILTER_IGNORE and c.get_global_rect().has_point(pos):
			return c
	return null
