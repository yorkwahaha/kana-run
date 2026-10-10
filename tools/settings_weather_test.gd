extends SceneTree
## 雨天、設定視窗、假名單元與存檔預設回歸（無需真實顯示卡）。
var _failed: Array[String] = []


func _init() -> void:
	_run.call_deferred()


func _check(ok: bool, message: String) -> void:
	if not ok:
		_failed.append(message)
	print("  %s %s" % ["PASS" if ok else "FAIL", message])


func _run() -> void:
	print("[settings-weather] progress and kana settings")
	_check(not SaveGame.DEFAULT_SETTINGS.has("katakana"), "移除舊的假名字形全域切換")
	_check(not SaveGame.DEFAULT_SETTINGS.has("auto_retry"), "移除自動再練設定")
	_check(not SaveGame.DEFAULT_SETTINGS.has("unlock_all"), "移除全部解鎖設定")
	_check(float(SaveGame.DEFAULT_SETTINGS["reduce_motion"]) == 1.0, "新玩家減少閃爍預設開啟")
	var curriculum = load("res://src/core/curriculum.gd").new()
	_check(curriculum.s("あ") == "あ", "平假名關卡仍呈現平假名")
	_check(curriculum.s("ア") == "ア", "片假名關卡仍呈現片假名")
	# 真正透過題庫產生題目，不能只測一個顯示函式。
	var hira := str(KanaDB.unit(KanaDB.Kind.SEION)[0][0])
	var kata := str(KanaDB.unit(KanaDB.Kind.KATA)[0][0])
	var hq: Dictionary = curriculum.make_question(hira, 0.0, 0)
	var kq: Dictionary = curriculum.make_question(kata, 0.0, 0)
	_check(str(hq["choices"][int(hq["target_index"])]) == hira, "清音題型的正解維持平假名")
	_check(str(kq["choices"][int(kq["target_index"])]) == kata, "片假名關卡的正解維持片假名")


	print("[settings-weather] rain and storm particles")
	var track = load("res://src/game/track.gd").new()
	root.add_child(track)
	await process_frame
	track.set_weather("rain", Vector3(1.4, -9.0, 0.0), Color(0.72, 0.86, 1.0))
	var petals: CPUParticles3D = track._petals
	_check(petals.amount == 560 and petals.spread <= 5.0 and petals.emission_box_extents.x == 18.0, "一般雨密度與小角度方向")
	_check(petals.angular_velocity_min == 0.0 and petals.angular_velocity_max == 0.0, "雨絲不隨機旋轉")
	_check(petals.mesh is BoxMesh and (petals.mesh as BoxMesh).size.x < 0.020, "雨絲改用細而低成本的盒狀粒子")
	var mat := (petals.mesh as BoxMesh).material as StandardMaterial3D
	_check(mat != null and mat.albedo_color.a < 0.5 and not mat.emission_enabled, "雨絲低透明度、沒有自發光")
	track.set_weather("storm", Vector3(3.2, -7.0, 0.0), Color(1.0, 0.55, 0.42))
	_check(petals.amount <= 700 and petals.spread <= 5.0 and petals.angular_velocity_max == 0.0, "暴雨增加有限粒子量、方向仍穩定")
	track.set_weather("", Vector3(0.6, -0.5, 0.0), Color(1, 0.8, 0.9))
	_check(petals.amount == 140 and petals.spread == 40.0 and petals.angular_velocity_max > 0.0 and petals.emission_box_extents.x == 22.0, "離開雨區後花瓣行為復原")
	track.queue_free()
	await process_frame

	print("[settings-weather] settings UI viewports")
	for dims in [Vector2i(1280, 720), Vector2i(960, 540), Vector2i(800, 450), Vector2i(640, 360)]:
		var vp := SubViewport.new()
		vp.size = dims
		root.add_child(vp)
		var ui: Control = load("res://src/ui/overlays.gd").new()
		vp.add_child(ui)
		# 獨立 SubViewport 的測試 Control 用固定尺寸；正式遊戲仍以全畫面錨點布局。
		ui.set_anchors_preset(Control.PRESET_TOP_LEFT)
		ui.size = Vector2(dims)
		await process_frame
		ui.show_settings(1)
		await process_frame
		await process_frame
		var done := ui.find_child("SettingsDone", true, false) as Control
		var scroll := ui.find_child("SettingsScroll", true, false) as ScrollContainer
		var can_fit := done != null and scroll != null
		if can_fit:
			var r := done.get_global_rect()
			var sc := scroll.get_global_rect()
			var content := scroll.get_child(0) as Control
			can_fit = r.position.y >= 4.0 and r.end.y <= float(dims.y) - 4.0 and sc.size.y > 0.0 and sc.end.y <= r.position.y and sc.end.x <= float(dims.x) - 4.0 and content.size.x <= sc.size.x + 1.0
		_check(can_fit, "設定完成鈕和捲動區位於 %dx%d 畫面內" % [dims.x, dims.y])
		vp.queue_free()
		await process_frame

	print("[settings-weather] 失敗 %d 項" % _failed.size())
	quit(0 if _failed.is_empty() else 1)
