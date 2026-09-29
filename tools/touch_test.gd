extends SceneTree
## 驗證觸控面板的版面。
##
## 為什麼不用截圖：桌機沒有觸控螢幕，面板預設隱藏，
## 截圖只會拍到空畫面，看不出按鈕位置對不對。
## 直接讀每顆按鈕在螢幕上的實際矩形，精確又不用開視窗。

func _init() -> void:
	_run.call_deferred()

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

	print("[touch] 失敗 %d 項" % fails)
	quit(0 if fails == 0 else 1)
