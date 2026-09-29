extends Node
## FontKit — 字型解析與快取。
##
## 專案內建三個子集化權重（見 tools/subset_fonts.py）：
##   ui.ttf      內文 / 說明文字
##   bold.ttf    標題 / 按鈕
##   display.ttf 題目與碑面等大字
## 若子集字型缺失（例如尚未執行工具），自動退回 SystemFont，
## 讓專案在未建置的機器上仍可執行。

const PATH_UI := "res://assets/fonts/ui.ttf"
const PATH_BOLD := "res://assets/fonts/bold.ttf"
const PATH_DISPLAY := "res://assets/fonts/display.ttf"

const SYSTEM_FALLBACKS := [
	"Zen Kaku Gothic New",
	"Noto Sans JP",
	"Yu Gothic UI",
	"Yu Gothic",
	"MS Gothic",
	"Meiryo",
	"sans-serif",
]

var ui: Font
var bold: Font
var display: Font


func _ready() -> void:
	ui = _load(PATH_UI, 0)
	bold = _load(PATH_BOLD, 1)
	display = _load(PATH_DISPLAY, 2)
	_install_as_default(ui)


func _load(path: String, weight: int) -> Font:
	if ResourceLoader.exists(path):
		var res := load(path)
		if res is Font:
			# 開啟 MSDF 會讓所有字形共用一張圖集，最省記憶體；
		# 但 MSDF 在極小字級會糊掉，標題另外用非 MSDF。
			return res as Font
	var sys := SystemFont.new()
	sys.font_names = PackedStringArray(SYSTEM_FALLBACKS)
	sys.font_weight = 400 + weight * 300
	sys.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_AUTO
	return sys


## 把字型設為整個專案的預設（ThemeDB），任何沒指定字型的 Control 都能顯示日文
func _install_as_default(font: Font) -> void:
	if font == null:
		return
	ThemeDB.fallback_font = font
