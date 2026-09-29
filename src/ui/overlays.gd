extends Control
## Overlays — 標題、單元選擇、暫停、遺物三選一、結算、設定、儀表板。
##
## 全部由 Main 以 show_*() 切換。每個畫面都是一次性的堆疊，
## 用 signals 回報玩家的決定，讓 Main 只負責流程。

signal start_requested(kinds: Array)
signal resume_requested
signal restart_requested
signal quit_to_title
signal relic_chosen(id: String)
signal continue_after_results
signal settings_changed

enum Page { NONE, TITLE, BRIEF, PAUSE, RELIC, RESULTS, SETTINGS, DASHBOARD }

var _stack: Control
var _pages: Dictionary = {}
var _shell_box: Dictionary = {}
var _relic_row: HBoxContainer
var _brief_row: HBoxContainer
const CARD_W := 224          ## 五張卡片統一寬度（清音／濁音半濁音／拗音／片假名／大滿貫）
var _stats_label: Label
var _settings_return := Page.TITLE
var _current := Page.NONE
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	theme = UiKit.theme()
	_stack = Control.new()
	_stack.name = "Stack"
	_stack.set_anchors_preset(Control.PRESET_FULL_RECT)
	_stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_stack)
	_rng.randomize()

	_build_title()
	_build_brief()
	_build_pause()
	_build_relic()
	_build_results()
	_build_settings()
	_build_dashboard()
	hide_all()


# ── 版面骨架 ────────────────────────────────────────────────────────────
func _new_page(id: int) -> Control:
	var scrim := UiKit.scrim(0.58)
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 40)
	margin.add_theme_constant_override("margin_right", 40)
	margin.add_theme_constant_override("margin_top", 28)
	margin.add_theme_constant_override("margin_bottom", 28)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(scrim)

	var box := VBoxContainer.new()
	box.name = "Box"
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 10)
	margin.add_child(box)

	var page := Control.new()
	page.set_anchors_preset(Control.PRESET_FULL_RECT)
	page.mouse_filter = Control.MOUSE_FILTER_STOP
	page.visible = false
	page.add_child(margin)
	_stack.add_child(page)

	_pages[id] = page
	_shell_box[id] = box
	return page


func _headline(box: VBoxContainer, text: String, size := 58) -> void:
	if text == "":
		return
	var t := UiKit.title(text, size)
	t.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(t)


func _caption(box: VBoxContainer, text: String) -> Label:
	var l := UiKit.label(text, 18, UiKit.INK_DIM)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(720, 0)
	box.add_child(l)
	return l


func _action_row(box: VBoxContainer) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 14)
	row.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(row)
	return row


func hide_all() -> void:
	for id in _pages.keys():
		(_pages[id] as Control).visible = false
	_current = Page.NONE


func _show(id: int) -> Control:
	hide_all()
	var page: Control = _pages[id]
	page.visible = true
	page.modulate.a = 0.0
	_current = id
	var tw := create_tween()
	tw.tween_property(page, "modulate:a", 1.0, 0.18)
	return page


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		match _current:
			Page.PAUSE:
				Sfx.ui_back()
				resume_requested.emit()
			Page.SETTINGS:
				_close_settings()
			Page.TITLE, Page.BRIEF, Page.DASHBOARD, Page.RESULTS:
				show_title()
			_:
				pass


# ── 標題 ────────────────────────────────────────────────────────────────
func _build_title() -> void:
	var page := _new_page(Page.TITLE)
	var box: VBoxContainer = _shell_box[Page.TITLE]

	var logo := UiKit.label("五十音疾走", 78, UiKit.INK, true)
	logo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	logo.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(logo)

	var sub := UiKit.label("KANA  RUN　—　五十音記憶跑酷", 21, UiKit.VIOLET)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(sub)

	var line := ColorRect.new()
	line.color = Color(0.45, 0.52, 1.0, 0.35)
	line.custom_minimum_size = Vector2(560, 2)
	line.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(line)

	var brief := _caption(box,
		"前方三座石碑，只有刻著正確假名的那座可以撞破。\n" +
		"題目不只考背誦 —— 越往後越考詞彙、混淆字與反應速度。\n" +
		"反應越快評價越高：PERFECT ＞ GREAT ＞ GOOD。\n" +
		"來不及就按 ↓ 棄題（那一題稍後還會再考），體力換取思考的餘裕。")
	brief.add_theme_font_size_override("font_size", 18)

	_stats_label = UiKit.label("", 15, Color(0.65, 0.68, 0.82))
	_stats_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_stats_label.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(_stats_label)

	var row := _action_row(box)

	var b_start := UiKit.primary_button("開始挑戰", UiKit.VIOLET)
	b_start.custom_minimum_size = Vector2(250, 60)
	b_start.pressed.connect(func(): Sfx.ui_tap(); show_brief())
	row.add_child(b_start)

	var b_dash := UiKit.button("學習儀表板")
	b_dash.custom_minimum_size = Vector2(190, 60)
	b_dash.pressed.connect(func(): Sfx.ui_tap(); show_dashboard())
	row.add_child(b_dash)

	var b_set := UiKit.button("設定")
	b_set.custom_minimum_size = Vector2(120, 60)
	b_set.pressed.connect(func(): Sfx.ui_tap(); show_settings(Page.TITLE))
	row.add_child(b_set)

	page.modulate.a = 1.0


# ── 單元選擇 ────────────────────────────────────────────────────────────
func _build_brief() -> void:
	var page := _new_page(Page.BRIEF)
	var box: VBoxContainer = _shell_box[Page.BRIEF]
	_headline(box, "選擇關卡")
	_caption(box, "每一關的題目都會依你的弱項自動加重；新音依五十音圖順序出場")

	# 五張等寬卡片並排（清音／濁音半濁音／拗音／片假名／大滿貫）
	_brief_row = HBoxContainer.new()
	_brief_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_brief_row.add_theme_constant_override("separation", 10)
	box.add_child(_brief_row)

	var brow := _action_row(box)
	var back := UiKit.button("返回")
	back.custom_minimum_size = Vector2(160, 50)
	back.pressed.connect(func(): Sfx.ui_back(); show_title())
	brow.add_child(back)

	page.modulate.a = 1.0


## 每次開啟都重建，否則「清除學習進度」之後掌握度還是舊的
func _rebuild_briefing() -> void:
	if _brief_row == null:
		return
	for c in _brief_row.get_children():
		c.queue_free()
	_brief_row.add_child(_unit_card(KanaDB.Kind.SEION))
	_brief_row.add_child(_unit_card(KanaDB.Kind.DAKUON))
	_brief_row.add_child(_unit_card(KanaDB.Kind.YOON))
	_brief_row.add_child(_unit_card(KanaDB.Kind.KATA))
	_brief_row.add_child(_grand_card())


func _unit_card(kind: int) -> PanelContainer:
	var c := UiKit.card(16, Color(0.07, 0.06, 0.14, 0.92), Color(0.45, 0.52, 1.0, 0.30))
	c.custom_minimum_size = Vector2(CARD_W, 238)
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	c.add_child(v)

	var name := UiKit.label(KanaDB.UNIT_NAMES[kind], 25, UiKit.INK, true)
	name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name.custom_minimum_size = Vector2(CARD_W - 32, 0)
	v.add_child(name)

	var sub := UiKit.label(KanaDB.UNIT_SUBTITLES[kind], 14, UiKit.INK_DIM)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(sub)

	# 原本這裡有一行黃色的假名範例（_preview_text）。
	# 拿掉了：它只是裝飾，卻佔掉 76px 並把卡片重心往下拉，
	# 而且「拗音篇」那組字換行後排版很亂。掌握度條本身已經夠說明進度了。

	var mastery := Srs.unit_mastery([kind])
	var m_label := UiKit.label("掌握度 %d%%" % int(round(mastery * 100.0)), 14, UiKit.INK_DIM)
	m_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(m_label)
	v.add_child(UiKit.bar(mastery, UiKit.JADE if mastery >= 0.7 else UiKit.GOLD, 8))

	var seen := 0
	for entry in KanaDB.unit(kind):
		if int(SaveGame.kana_record(entry[0]).get("seen", 0)) > 0:
			seen += 1
	var total := KanaDB.count_for(kind)
	var s_label := UiKit.label("接觸 %d / %d\n最高分 %d" % [
		seen, total, SaveGame.best_score(str(kind))], 13, UiKit.INK_DIM)
	s_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(s_label)

	v.add_child(UiKit.spacer(Vector2(0, 2), false))
	var play := UiKit.primary_button("出發", UiKit.VIOLET)
	play.pressed.connect(func(): Sfx.ui_tap(); start_requested.emit([kind]))
	v.add_child(play)

	return c


## 最後一張卡：208 音大滿貫
func _grand_card() -> PanelContainer:
	var c := UiKit.card(16, Color(0.11, 0.08, 0.05, 0.94), Color(UiKit.GOLD.r, UiKit.GOLD.g, UiKit.GOLD.b, 0.42))
	c.custom_minimum_size = Vector2(CARD_W, 238)
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	c.add_child(v)

	var name := UiKit.label("大滿貫", 25, UiKit.GOLD, true)
	name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(name)

	var sub := UiKit.label("208 音 · 平假名＋片假名", 13, UiKit.INK_DIM)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(sub)

	var kinds := [KanaDB.Kind.SEION, KanaDB.Kind.DAKUON, KanaDB.Kind.YOON, KanaDB.Kind.KATA]
	var mastery := Srs.unit_mastery(kinds)
	var m_label := UiKit.label("掌握度 %d%%" % int(round(mastery * 100.0)), 14, UiKit.INK_DIM)
	m_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(m_label)
	v.add_child(UiKit.bar(mastery, UiKit.GOLD, 8))

	var seen := 0
	for kana in KanaDB.all_kana():
		if int(SaveGame.kana_record(kana).get("seen", 0)) > 0:
			seen += 1
	var s_label := UiKit.label("接觸 %d / 208\n最高分 %d" % [
		seen, SaveGame.best_score("all")], 13, UiKit.INK_DIM)
	s_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(s_label)

	v.add_child(UiKit.spacer(Vector2(0, 2), false))
	var play := UiKit.primary_button("挑戰", UiKit.GOLD)
	play.pressed.connect(func():
		Sfx.ui_tap()
		start_requested.emit(kinds))
	v.add_child(play)

	return c


# ── 暫停 ────────────────────────────────────────────────────────────────
func _build_pause() -> void:
	var page := _new_page(Page.PAUSE)
	var box: VBoxContainer = _shell_box[Page.PAUSE]
	_headline(box, "暫停")

	var mk := func(text: String, accent: Color) -> Button:
		var b := UiKit.button(text, accent)
		b.custom_minimum_size = Vector2(320, 54)
		return b

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	v.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(v)

	var b := mk.call("繼續", UiKit.JADE)
	b.pressed.connect(func(): Sfx.ui_tap(); resume_requested.emit())
	v.add_child(b)

	var r := mk.call("重新開始本關", UiKit.VIOLET)
	r.pressed.connect(func(): Sfx.ui_tap(); restart_requested.emit())
	v.add_child(r)

	var s := mk.call("設定", UiKit.EDGE)
	s.pressed.connect(func(): Sfx.ui_tap(); show_settings(Page.PAUSE))
	v.add_child(s)

	var q := mk.call("回到標題", UiKit.INK_DIM)
	q.pressed.connect(func(): Sfx.ui_back(); quit_to_title.emit())
	v.add_child(q)

	page.modulate.a = 1.0


# ── 遺物三選一 ──────────────────────────────────────────────────────────
func _build_relic() -> void:
	var page := _new_page(Page.RELIC)
	var box: VBoxContainer = _shell_box[Page.RELIC]
	_headline(box, "獲得遺物")
	_caption(box, "每答對 10 題，從三件中取一件")

	_relic_row = HBoxContainer.new()
	_relic_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_relic_row.add_theme_constant_override("separation", 20)
	box.add_child(_relic_row)

	page.modulate.a = 1.0


func show_relic(owned: Dictionary) -> void:
	for c in _relic_row.get_children():
		c.queue_free()
	for def in RelicPool.roll(owned, _rng):
		_relic_row.add_child(_relic_card(def, owned))
	_show(Page.RELIC)


func _relic_card(def: Dictionary, owned: Dictionary) -> PanelContainer:
	var accent: Color = def["color"]
	var c := UiKit.card(20, Color(0.07, 0.06, 0.15, 0.96),
		Color(accent.r, accent.g, accent.b, 0.55))
	c.custom_minimum_size = Vector2(240, 290)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	c.add_child(v)

	var icon := UiKit.label(def["icon"], 62, accent, true)
	icon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(icon)

	var name := UiKit.label(def["name"], 30, UiKit.INK, true)
	name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(name)

	var have := int(owned.get(def["id"], 0))
	# 固定高度：不論有沒有持有，三張卡的按鈕都會在同一條線上
	var h := UiKit.label(
		("已持有 ×%d → ×%d" % [have, have + 1]) if have > 0 else "　",
		14, UiKit.GOLD)
	h.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	h.custom_minimum_size = Vector2(0, 20)
	v.add_child(h)

	var d := UiKit.label(def["desc"], 17, UiKit.INK_DIM)
	d.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	# 固定高度：說明文斷行與否都不影響三張卡的對齊
	d.custom_minimum_size = Vector2(200, 76)
	d.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	v.add_child(d)

	v.add_child(UiKit.spacer(Vector2(0, 4), false))

	var pick := UiKit.primary_button("取用", accent)
	pick.pressed.connect(func():
		Sfx.relic_pick()
		hide_all()
		relic_chosen.emit(def["id"]))
	v.add_child(pick)

	return c


# ── 結算 ────────────────────────────────────────────────────────────────
func _build_results() -> void:
	var page := _new_page(Page.RESULTS)
	page.modulate.a = 1.0


func show_results(data: Dictionary) -> void:
	var box: VBoxContainer = _shell_box[Page.RESULTS]
	for c in box.get_children():
		c.queue_free()

	var cleared: bool = data.get("cleared", false)
	_headline(box, "關卡制霸！" if cleared else "挑戰結束", 56)
	(box.get_child(box.get_child_count() - 1) as Label).add_theme_color_override(
		"font_color", UiKit.GOLD if cleared else UiKit.BLOOD)

	var stats := HBoxContainer.new()
	stats.alignment = BoxContainer.ALIGNMENT_CENTER
	stats.add_theme_constant_override("separation", 16)
	stats.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(stats)
	stats.add_child(_stat_chip("得分", str(int(data.get("score", 0))), UiKit.GOLD))
	stats.add_child(_stat_chip("答對", str(int(data.get("correct", 0))), UiKit.JADE))
	stats.add_child(_stat_chip("題數", str(int(data.get("answered", 0))), UiKit.INK))
	stats.add_child(_stat_chip("最高連段", str(int(data.get("best_combo", 0))), UiKit.VIOLET))
	stats.add_child(_stat_chip("撞毀", str(int(data.get("wrong", 0))), UiKit.BLOOD))
	stats.add_child(_stat_chip("閃避", str(int(data.get("dodged", 0))), UiKit.INK_DIM))

	# 學習診斷
	var diag := UiKit.card(16, Color(0.06, 0.055, 0.12, 0.9), Color(0.45, 0.52, 1.0, 0.28))
	diag.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	diag.custom_minimum_size = Vector2(820, 0)
	box.add_child(diag)

	var dv := VBoxContainer.new()
	dv.add_theme_constant_override("separation", 6)
	diag.add_child(dv)
	dv.add_child(UiKit.label("學習診斷　這一局最需要複習的假名", 19, UiKit.INK, true))

	var weak: Array = data.get("weakest", [])
	if weak.is_empty():
		dv.add_child(UiKit.label("累積紀錄還不夠，再跑一局就會出現分析。", 17, UiKit.INK_DIM))
	else:
		var grid := HFlowContainer.new()
		grid.add_theme_constant_override("h_separation", 8)
		grid.add_theme_constant_override("v_separation", 8)
		for kana in weak:
			var chip := UiKit.kana_chip(Curriculum.s(kana), KanaDB.romaji(kana), Srs.mastery(kana), 32)
			chip.tooltip_text = "正確率 %d%%　平均 %.0f ms" % [
				int(round(Srs.accuracy(kana) * 100.0)), Srs.avg_ms(kana)]
			grid.add_child(chip)
		dv.add_child(grid)

	var slow: Array = data.get("slowest", [])
	if not slow.is_empty():
		var parts: Array = []
		for kana in slow:
			parts.append("%s %s %.0fms" % [Curriculum.s(kana), KanaDB.romaji(kana), Srs.avg_ms(kana)])
		var line := UiKit.label("反應最慢：" + "　".join(parts), 16, UiKit.GOLD)
		line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		line.custom_minimum_size = Vector2(780, 0)
		dv.add_child(line)

	var row := _action_row(box)

	var again := UiKit.primary_button("再跑一次", UiKit.VIOLET)
	again.custom_minimum_size = Vector2(220, 54)
	again.pressed.connect(func(): Sfx.ui_tap(); restart_requested.emit())
	row.add_child(again)

	var home := UiKit.button("回到標題")
	home.custom_minimum_size = Vector2(200, 54)
	home.pressed.connect(func(): Sfx.ui_back(); quit_to_title.emit())
	row.add_child(home)

	_show(Page.RESULTS)


func _stat_chip(label_text: String, value: String, color: Color) -> PanelContainer:
	var c := UiKit.card(12, Color(0.06, 0.055, 0.12, 0.9), Color(color.r, color.g, color.b, 0.35))
	c.custom_minimum_size = Vector2(140, 0)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 0)
	var l := UiKit.label(label_text, 13, UiKit.INK_DIM)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(l)
	var val := UiKit.label(value, 26, color, true)
	val.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(val)
	c.add_child(v)
	return c


# ── 設定 ────────────────────────────────────────────────────────────────
func _build_settings() -> void:
	var page := _new_page(Page.SETTINGS)
	var box: VBoxContainer = _shell_box[Page.SETTINGS]
	_headline(box, "設定", 46)

	var card := UiKit.card(20, Color(0.06, 0.055, 0.12, 0.92))
	card.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	card.custom_minimum_size = Vector2(640, 0)
	box.add_child(card)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	card.add_child(v)

	v.add_child(_slider_row("主音量", "master_volume"))
	v.add_child(_slider_row("音效", "sfx_volume"))
	v.add_child(_slider_row("配樂", "music_volume"))
	v.add_child(_bgm_row())
	v.add_child(UiKit.hsep())
	v.add_child(_choice_row("假名", "katakana", ["平假名", "片假名"]))
	v.add_child(_choice_row("畫質", "quality", ["流暢", "平衡", "精細"]))
	v.add_child(_toggle_row("撞錯後自動再練", "auto_retry"))
	v.add_child(_toggle_row("解鎖全部關卡", "unlock_all"))
	v.add_child(_slider_row("畫面震動", "screen_shake"))
	v.add_child(_toggle_row("減少閃爍（無障礙）", "reduce_motion"))

	var row := _action_row(box)

	var back := UiKit.primary_button("完成", UiKit.JADE)
	back.custom_minimum_size = Vector2(220, 52)
	back.pressed.connect(func(): Sfx.ui_tap(); _close_settings())
	row.add_child(back)

	var wipe := UiKit.button("清除學習進度", UiKit.BLOOD)
	wipe.custom_minimum_size = Vector2(210, 52)
	wipe.pressed.connect(func():
		Sfx.ui_back()
		SaveGame.wipe_progress()
		Sfx.refresh_volumes()
		Curriculum.sync_settings()
		_rebuild_briefing()          # 讓關卡卡片的掌握度立即歸零
		settings_changed.emit())
	row.add_child(wipe)

	page.modulate.a = 1.0


func _slider_row(name: String, key: String) -> Control:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 14)
	var l := UiKit.label(name, 18, UiKit.INK)
	l.custom_minimum_size = Vector2(210, 0)
	h.add_child(l)

	var s := HSlider.new()
	s.min_value = 0.0
	s.max_value = 1.0
	s.step = 0.05
	s.value = float(SaveGame.get_setting(key, 0.8))
	s.custom_minimum_size = Vector2(280, 24)
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var val := UiKit.label("%d%%" % int(s.value * 100.0), 16, UiKit.INK_DIM)
	val.custom_minimum_size = Vector2(64, 0)
	s.value_changed.connect(func(x):
		val.text = "%d%%" % int(x * 100.0)
		SaveGame.set_setting(key, x)
		_on_setting_changed(key))
	h.add_child(s)
	h.add_child(val)
	return h


func _toggle_row(name: String, key: String) -> Control:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 14)
	var l := UiKit.label(name, 18, UiKit.INK)
	l.custom_minimum_size = Vector2(210, 0)
	h.add_child(l)
	var b := CheckButton.new()
	b.button_pressed = int(SaveGame.get_setting(key, 0)) == 1
	b.toggled.connect(func(on):
		SaveGame.set_setting(key, 1 if on else 0)
		_on_setting_changed(key))
	h.add_child(b)
	return h


## 背景音樂：模式切換 + 重播 + 換曲。
## 只要把 mp3/ogg 丟進 res://audio/music 就會出現在這裡。
func _bgm_row() -> Control:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)

	if not Sfx.has_external_bgm():
		var l := UiKit.label("背景音樂", 18, UiKit.INK)
		v.add_child(l)
		var info := UiKit.label(
			"目前使用內建程序化配樂。\n" +
			"把 mp3 / ogg 丟進專案的 audio/music/ 資料夾，\n" +
			"關掉遊戲再開（或等遊戲自動重掃 2 秒）就會生效。",
			15, UiKit.INK_DIM)
		info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.add_child(info)
		return v

	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 12)

	var l2 := UiKit.label("背景音樂", 18, UiKit.INK)
	l2.custom_minimum_size = Vector2(150, 0)
	h.add_child(l2)

	var mode := OptionButton.new()
	mode.add_item("單曲循環", 0)
	mode.add_item("全部輪播", 1)
	mode.selected = Sfx.bgm_mode()
	mode.custom_minimum_size = Vector2(150, 38)
	h.add_child(mode)

	var _track_label := UiKit.label(Sfx.bgm_label(), 15, UiKit.GOLD)
	_track_label.custom_minimum_size = Vector2(210, 0)
	_track_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	h.add_child(_track_label)

	mode.item_selected.connect(func(i):
		Sfx.set_bgm_mode(i)
		_track_label.text = Sfx.bgm_label())

	var b_replay := UiKit.button("重播", UiKit.JADE)
	b_replay.custom_minimum_size = Vector2(90, 38)
	b_replay.pressed.connect(func():
		Sfx.ui_tap()
		Sfx.replay_bgm()
		_track_label.text = Sfx.bgm_label())
	h.add_child(b_replay)

	var b_next := UiKit.button("下一首", UiKit.VIOLET)
	b_next.custom_minimum_size = Vector2(100, 38)
	b_next.pressed.connect(func():
		Sfx.ui_tap()
		Sfx.next_bgm()
		_track_label.text = Sfx.bgm_label())
	h.add_child(b_next)

	v.add_child(h)
	return v


func _choice_row(name: String, key: String, options: Array) -> Control:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 14)
	var l := UiKit.label(name, 18, UiKit.INK)
	l.custom_minimum_size = Vector2(210, 0)
	h.add_child(l)
	var o := OptionButton.new()
	for i in options.size():
		o.add_item(str(options[i]), i)
	o.selected = int(SaveGame.get_setting(key, 0))
	o.custom_minimum_size = Vector2(220, 40)
	o.item_selected.connect(func(i):
		SaveGame.set_setting(key, i)
		_on_setting_changed(key))
	h.add_child(o)
	return h


func _on_setting_changed(key: String) -> void:
	match key:
		"master_volume", "sfx_volume", "music_volume":
			Sfx.refresh_volumes()
		"katakana":
			Curriculum.sync_settings()
		"quality":
			get_tree().call_deferred("reload_current_scene")
	settings_changed.emit()


func show_settings(from: int) -> void:
	_settings_return = from
	_show(Page.SETTINGS)


func _close_settings() -> void:
	if _settings_return == Page.PAUSE:
		show_pause()
	else:
		show_title()


# ── 儀表板 ──────────────────────────────────────────────────────────────
func _build_dashboard() -> void:
	var page := _new_page(Page.DASHBOARD)
	page.modulate.a = 1.0


func show_dashboard() -> void:
	var box: VBoxContainer = _shell_box[Page.DASHBOARD]
	for c in box.get_children():
		c.queue_free()

	_headline(box, "學習儀表板", 46)
	_caption(box, "掌握度 = 正確率 × 連續答對 × 反應速度；下一局的出題權重就來自這張表")

	var overall := Srs.unit_mastery([KanaDB.Kind.SEION, KanaDB.Kind.DAKUON, KanaDB.Kind.YOON, KanaDB.Kind.KATA])
	_caption(box, "總掌握度 %d%%　·　已練習 %d 題　·　單詞本 %d 詞" % [
		int(round(overall * 100.0)), Srs.answered_count(), SaveGame.collected()])

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(1020, 360)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)

	var grid := VBoxContainer.new()
	grid.add_theme_constant_override("separation", 8)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(grid)

	for kind in [KanaDB.Kind.SEION, KanaDB.Kind.DAKUON, KanaDB.Kind.YOON, KanaDB.Kind.KATA]:
		grid.add_child(UiKit.label("%s　掌握度 %d%%" % [
			KanaDB.UNIT_NAMES[kind], int(round(Srs.unit_mastery([kind]) * 100.0))],
			20, UiKit.INK, true))
		var flow := HFlowContainer.new()
		flow.add_theme_constant_override("h_separation", 6)
		flow.add_theme_constant_override("v_separation", 6)
		for entry in KanaDB.unit(kind):
			var kana: String = entry[0]
			flow.add_child(UiKit.kana_chip(Curriculum.s(kana), KanaDB.romaji(kana), Srs.mastery(kana), 30))
		grid.add_child(flow)

	var row := _action_row(box)
	var back := UiKit.primary_button("返回", UiKit.JADE)
	back.custom_minimum_size = Vector2(240, 52)
	back.pressed.connect(func(): Sfx.ui_back(); show_title())
	row.add_child(back)

	_show(Page.DASHBOARD)


# ── 切換 ────────────────────────────────────────────────────────────────
func show_title() -> void:
	if _stats_label != null:
		var overall := Srs.unit_mastery([
			KanaDB.Kind.SEION, KanaDB.Kind.DAKUON, KanaDB.Kind.YOON, KanaDB.Kind.KATA])
		_stats_label.text = "總掌握度 %d%%　·　已練習 %d 題" % [
			int(round(overall * 100.0)), Srs.answered_count()]
	_show(Page.TITLE)


func show_brief() -> void:
	_rebuild_briefing()
	_show(Page.BRIEF)


func show_pause() -> void:
	_show(Page.PAUSE)
