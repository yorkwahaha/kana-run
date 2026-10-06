extends RefCounted
class_name UiKit

## UiKit — 全部 UI 在程式裡生成。沒有 .tscn、沒有圖片素材。
##
## 視覺原則：深色玻璃 + 極細光邊 + 大字。目標是「看起來像商業手遊」，
## 而不是像一個 HTML demo。

const INK := Color(0.96, 0.95, 0.99)
const INK_DIM := Color(0.66, 0.68, 0.80)
const PANEL := Color(0.055, 0.048, 0.105, 0.86)
const PANEL_SOLID := Color(0.075, 0.066, 0.135, 0.98)
const EDGE := Color(0.45, 0.52, 1.0, 0.35)
const EDGE_HOT := Color(0.70, 0.80, 1.0, 0.85)
const GOLD := Color(1.0, 0.82, 0.42)
const JADE := Color(0.35, 0.95, 0.72)
const BLOOD := Color(1.0, 0.36, 0.42)
const VIOLET := Color(0.68, 0.48, 1.0)

static var _theme: Theme
static var _flat_cache: Dictionary = {}


static func theme() -> Theme:
	if _theme != null:
		return _theme
	var t := Theme.new()

	t.default_font = FontKit.ui
	t.default_font_size = 20

	# ── Panel ──
	t.set_stylebox("panel", "PanelContainer", flat(PANEL, 18, EDGE, 2))
	t.set_stylebox("panel", "Panel", flat(PANEL, 18, EDGE, 2))

	# ── Label ──
	t.set_color("font_color", "Label", INK)
	t.set_font("font", "Label", FontKit.ui)
	t.set_font_size("font_size", "Label", 20)

	# ── Button ──
	var btn := flat(Color(0.13, 0.12, 0.24, 0.95), 14, EDGE, 2)
	btn.content_margin_left = 22
	btn.content_margin_right = 22
	btn.content_margin_top = 12
	btn.content_margin_bottom = 12
	var btn_hover := btn.duplicate() as StyleBoxFlat
	btn_hover.bg_color = Color(0.20, 0.19, 0.36, 0.98)
	btn_hover.border_color = EDGE_HOT
	var btn_press := btn.duplicate() as StyleBoxFlat
	btn_press.bg_color = Color(0.09, 0.08, 0.17, 1.0)
	var btn_disabled := btn.duplicate() as StyleBoxFlat
	btn_disabled.bg_color = Color(0.08, 0.08, 0.12, 0.6)
	btn_disabled.border_color = Color(0.3, 0.3, 0.4, 0.2)
	t.set_stylebox("normal", "Button", btn)
	t.set_stylebox("hover", "Button", btn_hover)
	t.set_stylebox("pressed", "Button", btn_press)
	t.set_stylebox("disabled", "Button", btn_disabled)
	var btn_focus := btn.duplicate() as StyleBoxFlat
	btn_focus.bg_color = Color(0.24, 0.22, 0.42, 0.99)
	btn_focus.border_color = EDGE_HOT
	t.set_stylebox("focus", "Button", btn_focus)
	t.set_stylebox("focus", "CheckButton", btn_focus)
	t.set_color("font_color", "Button", INK)
	t.set_color("font_hover_color", "Button", Color(1, 1, 1))
	t.set_color("font_focus_color", "Button", Color(1, 1, 1))
	t.set_color("font_pressed_color", "Button", INK_DIM)
	t.set_color("font_disabled_color", "Button", Color(0.45, 0.45, 0.55))
	t.set_font("font", "Button", FontKit.bold)
	t.set_font_size("font_size", "Button", 21)

	# ── ProgressBar ──
	t.set_stylebox("background", "ProgressBar", flat(Color(0.05, 0.05, 0.10, 0.9), 8, Color(0, 0, 0, 0), 0))
	t.set_stylebox("fill", "ProgressBar", flat(JADE, 8, Color(0, 0, 0, 0), 0))
	t.set_color("font_color", "ProgressBar", INK)

	# ── HSlider ──
	t.set_stylebox("slider", "HSlider", flat(Color(0.10, 0.10, 0.18, 1), 6, Color(0, 0, 0, 0), 0))
	t.set_stylebox("grabber_area", "HSlider", flat(JADE, 6, Color(0, 0, 0, 0), 0))
	var grabber := flat(Color(1, 1, 1, 1), 9, Color(0.3, 0.35, 0.6, 0.6), 2)
	t.set_stylebox("grabber", "HSlider", grabber)
	t.set_stylebox("grabber_highlight", "HSlider", grabber)

	# ── ScrollContainer / OptionButton ──
	var opt := flat(Color(0.10, 0.10, 0.20, 0.95), 12, EDGE, 2)
	opt.content_margin_left = 16
	opt.content_margin_right = 16
	opt.content_margin_top = 10
	opt.content_margin_bottom = 10
	t.set_stylebox("normal", "OptionButton", opt)
	t.set_stylebox("hover", "OptionButton", opt)
	t.set_stylebox("pressed", "OptionButton", opt)
	var opt_focus := opt.duplicate() as StyleBoxFlat
	opt_focus.border_color = EDGE_HOT
	t.set_stylebox("focus", "OptionButton", opt_focus)
	t.set_color("font_color", "OptionButton", INK)
	t.set_font("font", "OptionButton", FontKit.ui)
	t.set_font_size("font_size", "OptionButton", 20)
	t.set_stylebox("panel", "PopupMenu", flat(PANEL_SOLID, 12, EDGE, 2))
	t.set_color("font_color", "PopupMenu", INK)
	t.set_stylebox("hover", "PopupMenu", flat(Color(0.20, 0.19, 0.36, 1), 8, Color(0, 0, 0, 0), 0))

	_theme = t
	return _theme


static func flat(bg: Color, radius: int, border: Color = Color(0, 0, 0, 0), width: int = 0) -> StyleBoxFlat:
	var key := "%s|%d|%s|%d" % [bg.to_html(true), radius, border.to_html(true), width]
	if _flat_cache.has(key):
		return _flat_cache[key]
	var sb := _make_flat(bg, radius, border, width)
	_flat_cache[key] = sb
	return sb


## 需要在執行期改顏色的場合，一定要用這個（避免改到共用的快取）
static func flat_new(bg: Color, radius: int, border: Color = Color(0, 0, 0, 0), width: int = 0) -> StyleBoxFlat:
	return _make_flat(bg, radius, border, width)


static func _make_flat(bg: Color, radius: int, border: Color, width: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(radius)
	if width > 0:
		sb.set_border_width_all(width)
		sb.border_color = border
	return sb


# ── 元件工廠 ────────────────────────────────────────────────────────────
static func label(text: String, size := 20, color := INK, bold := false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_font_override("font", FontKit.bold if bold else FontKit.ui)
	# 說明文字不是按鈕。預設 STOP 會在平板上擋住底下真正該點的控制項。
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


## 大標題
static func title(text: String, size := 64, color := INK) -> Label:
	var l := label(text, size, color, true)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l


static func panel(pad := 20) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := flat(PANEL, 18, EDGE, 2)
	sb.content_margin_left = pad
	sb.content_margin_right = pad
	sb.content_margin_top = pad
	sb.content_margin_bottom = pad
	p.add_theme_stylebox_override("panel", sb)
	return p


static func card(pad := 14, bg := PANEL, border := EDGE) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := flat(bg, 14, border, 2)
	sb.content_margin_left = pad
	sb.content_margin_right = pad
	sb.content_margin_top = pad
	sb.content_margin_bottom = pad
	p.add_theme_stylebox_override("panel", sb)
	return p


static func button(text: String, accent := EDGE) -> Button:
	var b := Button.new()
	b.text = text
	var sb := flat(Color(0.13, 0.12, 0.24, 0.95), 14, accent, 2)
	b.add_theme_stylebox_override("normal", sb)
	var hov := sb.duplicate() as StyleBoxFlat
	hov.bg_color = Color(0.21, 0.20, 0.38, 0.99)
	b.add_theme_stylebox_override("hover", hov)
	var pr := sb.duplicate() as StyleBoxFlat
	pr.bg_color = Color(0.09, 0.08, 0.17, 1)
	b.add_theme_stylebox_override("pressed", pr)
	b.focus_mode = Control.FOCUS_ALL
	return b


## 只有字，沒有底與框。首頁入口用。
static func text_button(text: String, size := 32, color := INK) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_ALL
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.add_theme_color_override("font_focus_color", GOLD)
	b.add_theme_font_override("font", FontKit.bold)
	b.add_theme_font_size_override("font_size", size)
	b.add_theme_color_override("font_color", color)
	b.add_theme_color_override("font_hover_color", Color(1, 1, 1))
	b.add_theme_color_override("font_pressed_color", VIOLET)
	var empty := StyleBoxEmpty.new()
	empty.set_content_margin_all(14)
	b.add_theme_stylebox_override("normal", empty)
	b.add_theme_stylebox_override("hover", empty)
	b.add_theme_stylebox_override("pressed", empty)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.add_theme_stylebox_override("disabled", empty)
	return b


static func primary_button(text: String, accent := VIOLET) -> Button:
	var b := button(text, accent)
	var sb := flat(Color(0.32, 0.20, 0.55, 0.95), 14, accent.lightened(0.3), 2)
	b.add_theme_stylebox_override("normal", sb)
	var hov := sb.duplicate() as StyleBoxFlat
	hov.bg_color = accent.darkened(0.15)
	b.add_theme_stylebox_override("hover", hov)
	b.add_theme_color_override("font_color", Color(1, 1, 1))
	return b


static func spacer(min_size := Vector2.ZERO, expand := true) -> Control:
	var c := Control.new()
	c.custom_minimum_size = min_size
	if expand:
		c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		c.size_flags_vertical = Control.SIZE_EXPAND_FILL
	return c


static func hsep(color := Color(EDGE.r, EDGE.g, EDGE.b, 0.22)) -> ColorRect:
	var r := ColorRect.new()
	r.color = color
	r.custom_minimum_size = Vector2(0, 1)
	return r


static func bar(value01: float, fill: Color, height := 12.0) -> ProgressBar:
	var p := ProgressBar.new()
	p.min_value = 0.0
	p.max_value = 1.0
	p.value = value01
	p.show_percentage = false
	p.custom_minimum_size = Vector2(0, height)
	var bg := flat(Color(0.05, 0.05, 0.10, 0.9), int(height / 2), Color(0, 0, 0, 0), 0)
	p.add_theme_stylebox_override("background", bg)
	p.add_theme_stylebox_override("fill", flat(fill, int(height / 2), Color(0, 0, 0, 0), 0))
	return p


## 全螢幕漸層遮罩
static func scrim(alpha := 0.72) -> ColorRect:
	var r := ColorRect.new()
	r.color = Color(0.02, 0.015, 0.05, alpha)
	r.set_anchors_preset(Control.PRESET_FULL_RECT)
	r.mouse_filter = Control.MOUSE_FILTER_STOP
	return r


## 假名小卡：結果畫面與儀表板用
static func kana_chip(kana: String, romaji: String, mastery := -1.0, size := 34) -> PanelContainer:
	var p := card(8, Color(0.09, 0.08, 0.16, 0.95), Color(EDGE.r, EDGE.g, EDGE.b, 0.25))
	p.custom_minimum_size = Vector2(62, 0)
	# 注意：PanelContainer 會把「每一個」子節點都撐滿整個面板，
	# 所以這裡只能放一個 VBox，再由它去做垂直堆疊。
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 0)
	p.add_child(outer)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 0)
	outer.add_child(box)

	var k := label(kana, size, INK, true)
	k.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	k.custom_minimum_size = Vector2(46, 0)
	box.add_child(k)

	var r := label(romaji, 13, INK_DIM)
	r.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	r.custom_minimum_size = Vector2(46, 0)
	box.add_child(r)

	if mastery >= 0.0:
		var stripe := ColorRect.new()
		stripe.custom_minimum_size = Vector2(0, 4)
		stripe.color = (
			JADE if mastery >= 0.8 else
			GOLD if mastery >= 0.5 else
			BLOOD
		)
		outer.add_child(stripe)
	return p
