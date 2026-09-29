extends Control
## Hud — 遊戲中的抬頭顯示。
##
## 版面重心放在「題目」：中央上方的題卡是螢幕上最大的字，
## 因為這個遊戲的所有樂趣都來自「讀」。

const LANE_X := [-2.7, 0.0, 2.7]
const EXPLAIN_LIFE := 2.4        ## 錯題卡停留秒數

var _root: Control
var _q_card: PanelContainer
var _q_main: Label
var _q_sub: Label
var _q_kana: Label
var _open_hint: Label
var _grade_hint: Label
var _progress_overlay: Control
var _mini: MiniRunner
var _finish_flag: ColorRect
var _bar_holder: Control
var _timer: ProgressBar
var _timer_fill: StyleBoxFlat

var _unit_name: Label
var _progress_txt: Label
var _progress: ProgressBar
var _combo: Label
var _combo_box: Control

var _score: Label
var _speed: Label

var _stamina: ProgressBar
var _stamina_fill: StyleBoxFlat
var _stamina_txt: Label

var _banner: Label
var _zone_title: Label
var _zone_note: Label
var _zone_life := 0.0
var _zone_t := 0.0
var _sprint_box: Control
var _overdrive_box: Control
var _overdrive_vig: Control
var _overdrive_t := 0.0
var _zone_card: ColorRect
var _banner_t := 0.0
var _banner_life := 0.0
var _banner_color := Color.WHITE

var _relic_row: HFlowContainer
var _relic_chips: Array = []
var _touch_pad: Control
var _hint: Label

var _explain: PanelContainer
var _explain_title: Label
var _explain_body: VBoxContainer

var _combo_value := 0
var _combo_pulse := 0.0
var _explain_until_ms := 0      ## 錯題卡的關閉時限（真實時鐘，不受 time_scale 影響）


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme = UiKit.theme()
	_build()


func _build() -> void:
	_build_question()
	_build_top_left()
	_build_top_right()
	_build_bottom()
	_build_banner()
	_build_touch_pad()
	_build_explain()


# ── 題卡 ────────────────────────────────────────────────────────────────
func _build_question() -> void:
	_q_card = UiKit.card(16, Color(0.045, 0.040, 0.095, 0.80), Color(0.45, 0.52, 1.0, 0.30))
	_q_card.anchor_left = 0.5
	_q_card.anchor_right = 0.5
	_q_card.offset_left = -300
	_q_card.offset_right = 300
	_q_card.offset_top = 14
	_q_card.offset_bottom = 148
	_q_card.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_q_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_q_card)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_q_card.add_child(box)

	var cap := UiKit.label("題目", 13, UiKit.INK_DIM)
	cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(cap)

	_q_main = UiKit.label("", 62, UiKit.INK, true)
	_q_main.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_q_main.autowrap_mode = TextServer.AUTOWRAP_OFF
	box.add_child(_q_main)

	_q_sub = UiKit.label("", 19, UiKit.INK_DIM)
	_q_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_q_sub)

	_q_kana = UiKit.label("", 30, UiKit.GOLD, true)
	_q_kana.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_q_kana.visible = false
	box.add_child(_q_kana)

	# 障礙波才出現的「空道提示」
	_open_hint = UiKit.label("", 17, Color(0.35, 0.96, 0.68))
	_open_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_open_hint.visible = false
	box.add_child(_open_hint)

	# 新手提示：三級評價怎麼來的
	_grade_hint = UiKit.label(
		"答對時反應越快評價越高　·　PERFECT ＞ GREAT ＞ GOOD",
		14, Color(0.78, 0.82, 0.95, 0.85))
	_grade_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_grade_hint.visible = false
	box.add_child(_grade_hint)

	# 閱讀時限：把「速度壓力」變成看得見的一條線
	_timer = ProgressBar.new()
	_timer.min_value = 0.0
	_timer.max_value = 1.0
	_timer.value = 1.0
	_timer.show_percentage = false
	_timer.custom_minimum_size = Vector2(0, 6)
	_timer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bg := UiKit.flat_new(Color(0, 0, 0, 0.45), 3, Color(0, 0, 0, 0), 0)
	_timer_fill = UiKit.flat_new(UiKit.JADE, 3, Color(0, 0, 0, 0), 0)
	_timer.add_theme_stylebox_override("background", bg)
	_timer.add_theme_stylebox_override("fill", _timer_fill)
	box.add_child(_timer)


func _build_top_left() -> void:
	var box := VBoxContainer.new()
	box.anchor_left = 0.0
	box.anchor_top = 0.0
	box.offset_left = 16
	box.offset_top = 16
	box.add_theme_constant_override("separation", 4)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(box)

	_unit_name = UiKit.label("清音篇", 15, UiKit.INK_DIM)
	box.add_child(_unit_name)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	box.add_child(row)

	# 進度條與小跑步者必須疊在一起，所以用一個 Control 當容器，
	# 直接把兩者設成滿版錨點；放成 HBox 的兄弟節點會變成左右排列。
	# 小跑步者站在條的上方：8~10px 高的條子上塞一個小人會小到看不出是個人。
	var bar_holder := Control.new()
	bar_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar_holder.custom_minimum_size = Vector2(178, 34)
	row.add_child(bar_holder)

	# 未完成的部分要看得見 —— 那就是「還有多久」，
	# 底色太暗會讓整條進度看起來只有一小截。
	_progress = UiKit.bar(0.0, UiKit.VIOLET, 7)
	_progress.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_progress.anchor_left = 0.0
	_progress.anchor_right = 1.0
	_progress.anchor_top = 1.0
	_progress.anchor_bottom = 1.0
	_progress.offset_left = 0.0
	_progress.offset_right = 0.0
	_progress.offset_top = -7.0
	_progress.offset_bottom = 0.0
	_progress.add_theme_stylebox_override("background",
		UiKit.flat(Color(0.16, 0.16, 0.24, 0.95), 4, Color(0.6, 0.66, 0.9, 0.45), 1))
	bar_holder.add_child(_progress)

	_mini = MiniRunner.new()
	bar_holder.add_child(_mini)

	_progress_txt = UiKit.label("0/46", 15, UiKit.INK)
	_progress_txt.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(_progress_txt)

	_combo_box = VBoxContainer.new()
	row.add_child(_combo_box)
	_combo = UiKit.label("", 26, UiKit.GOLD, true)
	_combo_box.add_child(_combo)


func _build_top_right() -> void:
	var box := VBoxContainer.new()
	box.anchor_left = 1.0
	box.anchor_right = 1.0
	box.anchor_top = 0.0
	box.offset_left = -190
	box.offset_right = -16
	box.offset_top = 16
	box.alignment = BoxContainer.ALIGNMENT_END
	box.add_theme_constant_override("separation", 2)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(box)

	_score = UiKit.label("0", 34, UiKit.INK, true)
	_score.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	box.add_child(_score)

	_speed = UiKit.label("", 15, UiKit.INK_DIM)
	_speed.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	box.add_child(_speed)


func _build_bottom() -> void:
	var box := VBoxContainer.new()
	box.anchor_left = 0.5
	box.anchor_right = 0.5
	box.anchor_top = 1.0
	box.anchor_bottom = 1.0
	box.offset_left = -240
	box.offset_right = 240
	box.offset_top = -108
	box.offset_bottom = -12
	box.add_theme_constant_override("separation", 6)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(box)

	var head := HBoxContainer.new()
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(head)
	var lbl := UiKit.label("奔馳體力", 13, UiKit.INK_DIM)
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(lbl)
	_stamina_txt = UiKit.label("100", 13, UiKit.INK_DIM)
	head.add_child(_stamina_txt)

	_stamina = ProgressBar.new()
	_stamina.min_value = 0.0
	_stamina.max_value = 100.0
	_stamina.value = 100.0
	_stamina.show_percentage = false
	_stamina.custom_minimum_size = Vector2(0, 10)
	_stamina.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stamina.add_theme_stylebox_override("background", UiKit.flat_new(Color(0, 0, 0, 0.5), 5, Color(0, 0, 0, 0), 0))
	_stamina_fill = UiKit.flat_new(UiKit.JADE, 5, Color(0, 0, 0, 0), 0)
	_stamina.add_theme_stylebox_override("fill", _stamina_fill)
	box.add_child(_stamina)

	# 遺物一多就會超出畫面（實測 8 件會超出右邊界），
	# 用 HFlowContainer 讓晶片自動折行。
	# 寬度刻意設 0：真正的一局最多拿到 4 件，會自動排成一行；
	# 設太寬反而會把體力條一起撐寬，在手機上會爆掉。
	_relic_row = HFlowContainer.new()
	_relic_row.alignment = FlowContainer.ALIGNMENT_CENTER
	_relic_row.add_theme_constant_override("separation", 5)
	_relic_row.add_theme_constant_override("h_separation", 5)
	_relic_row.add_theme_constant_override("v_separation", 3)
	# 寬度交給外層的 480px，不要設 SIZE_SHRINK_CENTER ——
	# 那會讓 flow container 縮到最小寬度 0，結果一個晶片就換一行。
	_relic_row.add_theme_constant_override("v_separation", 3)
	_relic_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(_relic_row)

	_hint = UiKit.label("← → 或 A D 換線　·　↓ 棄題或蹲下　·　1 2 3 直選", 14, Color(0.7, 0.72, 0.85, 0.75))
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_hint)


# ── 判定橫幅 ────────────────────────────────────────────────────────────
func _build_banner() -> void:
	# 判定文字要避開題卡。題卡是 PanelContainer，高度會隨字型/DPI 撐開，
	# 寫死的座標一定會在不同螢幕上撞到，所以位置在 banner() 裡依
	# 題卡的實際下緣動態計算，這裡只先放一個暫用值。
	_banner = UiKit.label("", 54, Color.WHITE, true)
	_banner.anchor_left = 0.5
	_banner.anchor_right = 0.5
	_banner.anchor_top = 0.0
	_banner.anchor_bottom = 0.0
	_banner.offset_left = -400
	_banner.offset_right = 400
	_banner.offset_top = 200
	_banner.offset_bottom = 270
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_banner.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_banner.add_theme_constant_override("outline_size", 10)
	_banner.modulate.a = 0.0
	_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_banner)

	_build_zone_banner()
	_build_sprint_box()


## 換區卡：放在題卡右側上方的空白欄。
##
## 原本放在畫面中央（消失點高度），但那一帶正是遠方石碑所在，
## 換區提示一跳出來，下一題的碑面假名就被蓋住 —— 等於每次切區必撞一題。
## 判斷橫幅已經占了題卡正下方那條帶子，所以這裡挑右側這塊永遠空著的區域。
func _build_zone_banner() -> void:
	_zone_card = ColorRect.new()
	_zone_card.color = Color(0, 0, 0, 0.45)
	_zone_card.anchor_left = 0.0
	_zone_card.anchor_right = 1.0
	_zone_card.anchor_top = 0.0
	_zone_card.anchor_bottom = 0.0
	_zone_card.offset_left = 952
	_zone_card.offset_right = -14
	_zone_card.offset_top = 114
	_zone_card.offset_bottom = 224
	_zone_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_zone_card.modulate.a = 0.0
	add_child(_zone_card)

	_zone_title = UiKit.label("", 24, Color.WHITE, true)
	_zone_title.anchor_left = 1.0
	_zone_title.anchor_right = 1.0
	_zone_title.anchor_top = 0.0
	_zone_title.anchor_bottom = 0.0
	_zone_title.offset_left = -322
	_zone_title.offset_right = -20
	_zone_title.offset_top = 128
	_zone_title.offset_bottom = 166
	_zone_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_zone_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_zone_title.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_zone_title.add_theme_constant_override("outline_size", 8)
	_zone_title.modulate.a = 0.0
	_zone_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_zone_title)

	_zone_note = UiKit.label("", 15, Color(0.82, 0.90, 1.0))
	_zone_note.anchor_left = 1.0
	_zone_note.anchor_right = 1.0
	_zone_note.anchor_top = 0.0
	_zone_note.anchor_bottom = 0.0
	_zone_note.offset_left = -322
	_zone_note.offset_right = -20
	_zone_note.offset_top = 172
	_zone_note.offset_bottom = 210
	_zone_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_zone_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_zone_note.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_zone_note.add_theme_constant_override("outline_size", 6)
	_zone_note.modulate.a = 0.0
	_zone_note.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_zone_note)


## 衝刺關指示：固定在左上角連段下方，只要在衝刺就一直亮著
func _build_sprint_box() -> void:
	_sprint_box = UiKit.card(5, Color(0.35, 0.16, 0.04, 0.80), UiKit.GOLD)
	_sprint_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 5)
	row.add_child(UiKit.label("衝刺", 15, UiKit.GOLD, true))
	row.add_child(UiKit.label("得分 ×2", 14, Color(1.0, 0.92, 0.70)))
	_sprint_box.add_child(row)
	_sprint_box.visible = false
	# 放在左上角進度條的正下方，不要跟連段數字疊在一起
	_sprint_box.anchor_left = 0.0
	_sprint_box.anchor_top = 0.0
	_sprint_box.offset_left = 16
	_sprint_box.offset_top = 92
	add_child(_sprint_box)
	_build_overdrive_box()


## 極限指示：放在衝刺框的正下方，兩者不會同時亮但位置一致，看起來像同一組狀態
func _build_overdrive_box() -> void:
	_overdrive_box = UiKit.card(5, Color(0.30, 0.10, 0.05, 0.85), UiKit.GOLD)
	_overdrive_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.add_child(UiKit.label("極限", 16, UiKit.GOLD, true))
	row.add_child(UiKit.label("得分 ×3　碑面閃爍", 14, Color(1.0, 0.86, 0.55)))
	_overdrive_box.add_child(row)
	_overdrive_box.anchor_left = 0.0
	_overdrive_box.anchor_top = 0.0
	_overdrive_box.offset_left = 16
	_overdrive_box.offset_top = 124
	_overdrive_box.visible = false
	add_child(_overdrive_box)

	# 暗角：用四個漸層色塊框住畫面，比單一 ColorRect 便宜且不會糊住中央
	_build_overdrive_vignette()


## 暗角：四條 LinearGradient 邊框拼出來的，不要用整片半透明色塊。
##
## 整片 ColorRect 會把「邊緣變暗」變成「整個畫面變灰」——
## 中央的題目跟跑者一起被洗白，反而看不清。真正的暗角必須
## 中間完全透明、只有外圈壓暗。
func _build_overdrive_vignette() -> void:
	var holder := Control.new()
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(holder)

	var edges := {
		"t": [0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0, 0.16],
		"b": [0.0, 1.0, 1.0, 1.0, 0.0, 0.84, 1.0, 1.0],
		"l": [0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.20, 1.0],
		"r": [1.0, 0.0, 1.0, 1.0, 0.80, 0.0, 1.0, 1.0],
	}
	for key in edges:
		var e: Array = edges[key]
		var g := Gradient.new()
		g.set_color(0, Color(0.04, 0.01, 0.09, 0.92))
		g.set_color(1, Color(0.04, 0.01, 0.09, 0.0))
		var grad := GradientTexture2D.new()
		grad.gradient = g
		grad.width = 128
		grad.height = 128
		grad.fill_from = Vector2(0.5, 0.5)
		grad.fill_to = Vector2(0.5, 0.0)
		if key == "b":
			grad.fill_to = Vector2(0.5, 1.0)
		elif key == "l":
			grad.fill_to = Vector2(0.0, 0.5)
		elif key == "r":
			grad.fill_to = Vector2(1.0, 0.5)

		var rect := TextureRect.new()
		rect.texture = grad
		rect.stretch_mode = TextureRect.STRETCH_SCALE
		rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		rect.anchor_left = float(e[0])
		rect.anchor_top = float(e[1])
		rect.anchor_right = float(e[2])
		rect.anchor_bottom = float(e[3])
		rect.offset_left = 0.0
		rect.offset_top = 0.0
		rect.offset_right = 0.0
		rect.offset_bottom = 0.0
		rect.modulate = Color(1, 1, 1, 1)
		rect.name = "Vig" + str(key)
		holder.add_child(rect)

	_overdrive_vig = holder


## 貼在題卡正下方，題卡多高都不會重疊。
## 留 20px 間隔：橫幅會放大到 1.35 倍，描邊也會往外撐。
func _reposition_banner() -> void:
	var top := 14.0 + 148.0 + 20.0
	if is_instance_valid(_q_card):
		top = _q_card.get_global_rect().end.y + 20.0
	var h := 72.0
	_banner.offset_top = top
	_banner.offset_bottom = top + h
	_banner.pivot_offset = Vector2(_banner.size.x * 0.5, h * 0.5)


# ── 觸控面板 ────────────────────────────────────────────────────────────
func _build_touch_pad() -> void:
	_touch_pad = Control.new()
	_touch_pad.anchor_left = 0.0
	_touch_pad.anchor_right = 1.0
	_touch_pad.anchor_top = 1.0
	_touch_pad.anchor_bottom = 1.0
	_touch_pad.offset_top = -190
	_touch_pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_touch_pad.visible = DisplayServer.is_touchscreen_available()
	add_child(_touch_pad)

	var mk := func(text: String) -> Button:
		var b := Button.new()
		b.text = text
		b.custom_minimum_size = Vector2(96, 74)
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_font_override("font", FontKit.bold)
		b.add_theme_font_size_override("font_size", 26)
		b.add_theme_color_override("font_color", Color(1, 1, 1, 0.9))
		var sb := UiKit.flat_new(Color(0.10, 0.10, 0.20, 0.45), 20, Color(0.5, 0.58, 1.0, 0.35), 2)
		b.add_theme_stylebox_override("normal", sb)
		var hv := UiKit.flat_new(Color(0.24, 0.24, 0.42, 0.68), 20, Color(0.6, 0.68, 1.0, 0.55), 2)
		b.add_theme_stylebox_override("hover", hv)
		b.add_theme_stylebox_override("pressed", hv)
		return b

	var left: Button = mk.call("左")
	left.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	left.offset_left = 22
	left.offset_top = -88
	left.offset_right = 118
	left.offset_bottom = -14
	_touch_pad.add_child(left)
	left.pressed.connect(func(): _emit_lane(-1))

	var mid: Button = mk.call("中")
	mid.anchor_left = 0.5
	mid.anchor_right = 0.5
	mid.offset_left = -48
	mid.offset_right = 48
	mid.offset_top = -88
	mid.offset_bottom = -14
	_touch_pad.add_child(mid)
	mid.pressed.connect(func(): _emit_lane(0))

	var right: Button = mk.call("右")
	right.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	right.offset_left = -118
	right.offset_top = -88
	right.offset_right = -22
	right.offset_bottom = -14
	_touch_pad.add_child(right)
	right.pressed.connect(func(): _emit_lane(1))

	var duck: Button = mk.call("閃")
	duck.anchor_left = 0.5
	duck.anchor_right = 0.5
	duck.offset_left = -48
	duck.offset_right = 48
	duck.offset_top = -172
	duck.offset_bottom = -98
	_touch_pad.add_child(duck)
	duck.pressed.connect(func(): _emit_dodge())


signal lane_requested(lane: int)
signal dodge_requested


func _emit_lane(l: int) -> void:
	Sfx.ui_tap()
	lane_requested.emit(l)


func _emit_dodge() -> void:
	Sfx.ui_tap()
	dodge_requested.emit()


# ── 錯題解說卡 ──────────────────────────────────────────────────────────
func _build_explain() -> void:
	_explain = UiKit.card(12, Color(0.085, 0.040, 0.075, 0.985), Color(1.0, 0.36, 0.42, 0.65))
	# 貼在跑者與體力條之間那條空白帶，從下緣往上長。
	# 放在題卡下方還是會壓到下一題 —— 題卡的位置會隨字型/DPI 變動，
	# 兩者不可能永遠不打架。而畫面下半部除了跑者之外本來就是空的。
	# 答錯時本來就不彈判定橫幅，所以這裡不會互相蓋到。
	_explain.anchor_left = 0.5
	_explain.anchor_right = 0.5
	_explain.anchor_top = 1.0
	_explain.anchor_bottom = 1.0
	_explain.offset_left = -300
	_explain.offset_right = 300
	_explain.offset_top = -112
	_explain.offset_bottom = -112
	_explain.grow_horizontal = Control.GROW_DIRECTION_BOTH
	# 往上長：內容有多少就往上撐多高，不會掉出畫面底部
	_explain.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_explain.visible = false
	_explain.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_explain)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 3)
	_explain.add_child(box)

	_explain_title = UiKit.label("", 26, UiKit.BLOOD, true)
	_explain_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_explain_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_explain_title)

	_explain_body = VBoxContainer.new()
	_explain_body.add_theme_constant_override("separation", 1)
	_explain_body.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(_explain_body)


## 錯題卡貼在體力條上方。底緣固定，長度由內容決定。
func _reposition_explain() -> void:
	var bottom := -112.0
	_explain.offset_bottom = bottom
	_explain.offset_top = bottom


# ── 對外 API ────────────────────────────────────────────────────────────
func set_question(q: Dictionary, show_answer := false) -> void:
	_q_main.text = q.get("prompt", "")
	_q_sub.text = q.get("prompt_sub", "")
	_open_hint.visible = false
	var big := 62
	if q.get("type", 0) == Curriculum.QType.WORD_BLANK:
		big = 54
	elif _q_main.text.length() > 6:
		big = 40
	_q_main.add_theme_font_size_override("font_size", big)
	_q_kana.visible = show_answer
	if show_answer:
		_q_kana.text = "%s  %s" % [Curriculum.s(q["kana"]), q.get("romaji", "")]


func set_unit(name: String) -> void:
	_unit_name.text = name


func set_progress(idx: int, total: int) -> void:
	_progress_txt.text = "%d/%d" % [idx, total]
	var v := 0.0 if total <= 0 else float(idx) / float(total)
	_progress.value = v
	# 小跑步者沿著進度條往終點移動，讓「還有多久」一眼看得出來
	_mini.progress = v
	_mini.speed01 = clampf((float(idx) / maxf(1.0, float(total))) * 3.0, 0.35, 1.0)


func set_score(v: int) -> void:
	_score.text = str(v)


func set_speed_kmh(v: int) -> void:
	_speed.text = "%d km/h" % v


func set_combo(mult: float, chain: int) -> void:
	_combo_value = chain
	if chain >= 2:
		_combo.text = "×%.1f  %d 連" % [mult, chain]
		_combo.visible = true
		_combo_pulse = 1.0
	else:
		_combo.text = ""
		_combo.visible = false


func set_stamina(v: float, max_v: float) -> void:
	_stamina.max_value = max_v
	_stamina.value = v
	var pct := 0.0 if max_v <= 0.0 else v / max_v
	_stamina_txt.text = "%d%%" % int(round(pct * 100.0))
	_stamina_fill.bg_color = (
		UiKit.BLOOD if pct < 0.25 else
		UiKit.GOLD if pct < 0.55 else
		UiKit.JADE
	)


func set_timer(ratio: float, urgent := false) -> void:
	_timer.value = clampf(ratio, 0.0, 1.0)
	_timer_fill.bg_color = UiKit.BLOOD if urgent else UiKit.JADE


func set_relics(owned: Dictionary) -> void:
	for c in _relic_row.get_children():
		c.queue_free()
	_relic_chips.clear()
	for id in owned.keys():
		var n := int(owned[id])
		if n <= 0:
			continue
		var d := RelicPool.get_def(id)
		if d.is_empty():
			continue
		var chip := UiKit.card(5, Color(0.10, 0.09, 0.19, 0.85), Color(d["color"].r, d["color"].g, d["color"].b, 0.55))
		# 單行：圖示 + 名稱 + 數值。底欄只有幾十像素高，
		# 兩行版本一多就會被畫面下緣切掉。
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 3)
		row.add_child(UiKit.label(d["icon"], 14, d["color"], true))
		row.add_child(UiKit.label(d["name"], 13, UiKit.INK_DIM))
		if n > 1:
			row.add_child(UiKit.label("×%d" % n, 12, d["color"]))
		var st := UiKit.label("", 12, d["color"])
		row.add_child(st)
		chip.add_child(row)

		_relic_row.add_child(chip)
		_relic_chips.append({"id": id, "n": n, "label": st})


## 每幀更新遺物的即時數值（約 6Hz 即可，不會有可見成本）
## 進度條上的小跑步者。
##
## 為什麼要自己畫：進度條本來只是一條填色的長條，玩家看不出「還有多久」。
## 放一個會跑的小人沿著條往終點旗移動，剩餘距離就變成一眼可讀的資訊。
## 用 _draw 手繪而不是字型，確保不受字型子集影響。
class MiniRunner extends Control:
	var progress := 0.0       ## 0 = 起點, 1 = 終點
	var speed01 := 0.6
	var _phase := 0.0

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		# 直接指派錨點與邊界，不要用 set_anchors_preset()：
		# 那個 API 在 _ready 階段對這個父層（普通 Control）不會給出正確的尺寸，
		# 實測 mini.size 會是 (0, 5)，整個人就畫不見了。
		anchor_left = 0.0
		anchor_top = 0.0
		anchor_right = 1.0
		anchor_bottom = 1.0
		offset_left = 0.0
		offset_top = 0.0
		offset_right = 0.0
		offset_bottom = 0.0

	func _process(delta: float) -> void:
		_phase += delta * (7.0 + speed01 * 7.0)
		queue_redraw()

	func _draw() -> void:
		var w := size.x
		var h := size.y
		if w <= 0.0:
			return
		# 小人站在進度條上方那截空間裡
		var band := h - 7.0
		var k := band * 0.80            # 身高係數
		var base := band * 0.98         # 腳底位置

		# 終點旗
		var fx := w - 2.0
		draw_line(Vector2(fx, 1.0), Vector2(fx, base), Color(1.0, 0.72, 0.45, 0.95), 2.0)
		draw_line(Vector2(fx, 2.0), Vector2(fx - 6.0, 5.0), Color(1.0, 0.72, 0.45, 0.8), 1.5)

		var cx := lerpf(5.0, fx - 4.0, clampf(progress, 0.0, 1.0))
		var cy := base
		var c := Color(1.0, 0.94, 0.72, 0.99)
		# 頭
		draw_circle(Vector2(cx, cy - k * 0.88), k * 0.24, c)
		# 身體（微微前傾）
		var lean := 0.16
		draw_line(Vector2(cx, cy - k * 0.58), Vector2(cx - k * lean, cy - k * 0.02), c, 2.0)
		# 手臂：與腿反相
		var s := sin(_phase)
		var s2 := sin(_phase + PI)
		draw_line(Vector2(cx, cy - k * 0.48), Vector2(cx + s * k * 0.34, cy - k * 0.16), c, 1.6)
		draw_line(Vector2(cx, cy - k * 0.48), Vector2(cx + s2 * k * 0.34, cy - k * 0.16), c, 1.6)
		# 腿
		draw_line(Vector2(cx - k * lean, cy - k * 0.06), Vector2(cx + s2 * k * 0.40, cy), c, 1.8)
		draw_line(Vector2(cx - k * lean, cy - k * 0.06), Vector2(cx + s * 0.40 * k, cy), c, 1.8)


func set_relic_status(ctx: Dictionary) -> void:
	for c in _relic_chips:
		var lbl: Label = c["label"]
		var s := RelicPool.status_short(c["id"], ctx)
		if lbl.text != s:
			lbl.text = s


## 新手提示：只在前幾題出現一次，講清楚三級評價怎麼來的。
## 沒有這行的話，PERFECT / GREAT 兩個字對第一次玩的人完全沒有意义 ——
## 他不知道那是什麼，也不知道自己為什麼一直只拿到 GREAT。
func set_grade_hint(shown: bool) -> void:
	_grade_hint.visible = shown
	if shown:
		_grade_hint.modulate.a = 1.0


## 立刻收掉換區卡（暖機用）
func hide_zone() -> void:
	_zone_life = 0.0
	_zone_title.modulate.a = 0.0
	_zone_note.modulate.a = 0.0
	_zone_card.modulate.a = 0.0


## 障礙波提示：直接寫出哪一條是綠色空道
func set_barrier_hint(covered: int) -> void:
	var open_lane := 0
	for i in 3:
		if (covered & (1 << i)) == 0:
			open_lane = i
	_q_sub.text = "綠色空道站著直接過　·　紅白條要蹲下（扣體力）"
	_q_kana.visible = false
	_timer.value = 1.0
	_open_hint.text = "空道 → 第 %d 道" % (open_lane + 1)
	_open_hint.visible = true


## 換區大橫幅：整塊畫面中央偏上的一行，停留比較久
func banner_zone(title: String, place: String, note: String) -> void:
	_zone_life = 2.6
	_zone_t = 0.0
	_zone_title.text = "%s・%s" % [title, place]
	_zone_note.text = note
	_zone_title.modulate.a = 0.0
	_zone_note.modulate.a = 0.0
	_zone_card.modulate.a = 0.0
	_zone_title.pivot_offset = _zone_title.size * 0.5
	_zone_title.scale = Vector2(0.8, 0.8)
	_zone_note.pivot_offset = _zone_note.size * 0.5
	_zone_note.scale = Vector2(0.8, 0.8)


func _tick_zone(delta: float) -> void:
	if _zone_life <= 0.0:
		return
	_zone_t += delta
	var t := _zone_t
	# 0.00-0.12 彈入，0.12-0.75 停留，0.75-1.00 淡出
	var a := 1.0
	if t < 0.30:
		a = t / 0.30
	elif t > 1.95:
		a = clampf(1.0 - (t - 1.95) / 0.65, 0.0, 1.0)
	var ease := 1.0 - pow(1.0 - clampf(t / 0.30, 0.0, 1.0), 3.0)
	_zone_title.modulate.a = a
	_zone_note.modulate.a = a * 0.9
	_zone_card.modulate.a = a
	_zone_title.scale = Vector2.ONE * (0.8 + 0.2 * ease)
	_zone_note.scale = Vector2.ONE * (0.85 + 0.15 * ease)
	if t >= 2.6:
		_zone_life = 0.0
		_zone_title.modulate.a = 0.0
		_zone_note.modulate.a = 0.0
		_zone_card.modulate.a = 0.0


## 衝刺關指示：畫面左上角持續顯示，玩家才知道現在有加成
func set_sprint(on: bool) -> void:
	_sprint_box.visible = on


## 極限狀態：左上角標籤 + 全螢幕暗角。
##
## 暗角不只是裝飾：它讓「邊緣變暗」變成視野的一部分，
## 玩家會下意識覺得自己被逼到角落，壓力比數字更直接。
func set_overdrive(on: bool) -> void:
	if _overdrive_box != null and is_instance_valid(_overdrive_box):
		_overdrive_box.visible = on
	if _overdrive_vig != null and is_instance_valid(_overdrive_vig):
		_overdrive_vig.visible = on
	_overdrive_t = 0.0


func _tick_overdrive(delta: float) -> void:
	# 用 _overdrive_box 的可見性當狀態來源，不要在這裡另存一份布林：
	# 兩份狀態遲早會不同步，然後暗角會在極限已經結束時還留在畫面上
	if _overdrive_box == null or not is_instance_valid(_overdrive_box) or not _overdrive_box.visible:
		return
	_overdrive_t += delta
	# 前 0.35 秒收緊、後 0.5 秒放鬆成呼吸 —— 一直滿會變成背景雜訊
	var k := clampf(_overdrive_t / 0.85, 0.0, 1.0)
	var pulse := 0.55 + 0.45 * sin(_overdrive_t * 4.2)
	var a := lerpf(0.60, 0.34, k) * lerpf(0.75, 1.0, pulse)
	if _overdrive_vig != null and is_instance_valid(_overdrive_vig):
		_overdrive_vig.modulate = Color(1, 1, 1, a)
	if _overdrive_box != null and is_instance_valid(_overdrive_box) and _overdrive_box is Control:
		var c := _overdrive_box as Control
		c.modulate = Color(1, 1, 1, lerpf(1.35, 1.0, k))


func clear_sprint() -> void:
	_sprint_box.visible = false


func banner(text: String, color: Color, life := 0.7) -> void:
	_banner.text = text
	_banner.add_theme_color_override("font_color", color)
	_banner_life = life
	_banner_t = 0.0
	_banner.modulate.a = 1.0
	_reposition_banner()
	_banner.pivot_offset = Vector2(_banner.size.x * 0.5, _banner.size.y * 0.5)
	_banner.scale = Vector2(1.35, 1.35)


func show_explain(card: Dictionary, title := "記住這個", life := 2.4) -> void:
	for c in _explain_body.get_children():
		c.queue_free()
	_explain_title.text = "%s　%s  %s" % [title, card["kana"], card["romaji"]]
	for line in card["lines"]:
		var l := UiKit.label(str(line), 18, UiKit.INK)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_explain_body.add_child(l)
	if not card["confusions"].is_empty():
		var sep := UiKit.label("容易混淆：" + "　".join(card["confusions"]), 15, UiKit.GOLD)
		sep.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		sep.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_explain_body.add_child(sep)
	_reposition_explain()
	_explain.visible = true
	_explain.modulate.a = 0.0
	# 用真實時鐘計時：答錯時的 hit-stop 會把 time_scale 壓到 0.06，
	# 如果跟著 scaled delta 走，淡入會被拉長到好幾秒。
	_explain_until_ms = Time.get_ticks_msec() + int(life * 1000.0)
	var tw := create_tween()
	tw.set_ignore_time_scale(true)
	tw.tween_property(_explain, "modulate:a", 1.0, 0.16)


func hide_explain() -> void:
	_explain_until_ms = 0
	_explain.visible = false
	_explain.modulate.a = 0.0


func set_hint_visible(v: bool) -> void:
	_hint.visible = v


func _process(delta: float) -> void:
	_tick_zone(delta)
	_tick_overdrive(delta)
	# 錯題解說卡會自己消失，不會一直擋住畫面。
	# 暫停時不要倒數，否則玩家一暫停就看不到剛剛的講解。
	if _explain_until_ms > 0 and not get_tree().paused:
		var left := _explain_until_ms - Time.get_ticks_msec()
		if left <= 0:
			hide_explain()
		elif left < 350:
			# 最後 0.35 秒淡出，不要突然消失
			_explain.modulate.a = clampf(float(left) / 350.0, 0.0, 1.0)

	if _banner_life > 0.0:
		_banner_t += delta
		var k := clampf(_banner_t / _banner_life, 0.0, 1.0)
		_banner.modulate.a = 1.0 - k * k
		_banner.scale = Vector2.ONE * lerpf(1.35, 0.98, minf(1.0, k * 3.2))
		if k >= 1.0:
			_banner_life = 0.0
			_banner.modulate.a = 0.0
	if _combo_pulse > 0.0:
		_combo_pulse = maxf(0.0, _combo_pulse - delta * 3.0)
		_combo.modulate = Color(1, 1, 1, 1).lerp(Color(1.6, 1.4, 0.8, 1), _combo_pulse)
