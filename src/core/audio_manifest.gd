class_name AudioManifest
extends RefCounted
## 音訊與字型的資源清單（由 tools/gen_manifest.py 產生，請勿手動編輯）。
##
## 這個檔案存在的理由是**兩件在匯出後會壞掉的事**：
##
## 1. 打包階段：音訊與字型全都是用字串路徑在執行期動態載入的，
##    沒有任何場景或 .tscn 參照。`export_filter="all_resources"`
##    只打包有相依關係的資源，於是整批音訊從 pck 裡消失。
##
## 2. 執行階段：`DirAccess.get_files_at("res://audio/music/")`
##    在匯出後的 pck 裡讀不到目錄內容。桌機跑原始檔案正常，
##    網頁版就是空的。
##
## 兩者的症狀都是「匯出成功、沒有任何錯誤訊息」，但遊戲會安靜地
## 退回內建程序化配樂，設定畫面寫「目前使用內建程序化配樂」。
## 線上版曾因此整整少了 6.4MB 音訊，只有比對 pck 大小或
## 印出 BGM 清單才看得出來。
##
## 這個檔案同時解決兩者：每個項目都是 preload（建立相依關係），
## 並提供分組清單供執行期查詢。
##
## 改完 audio/ 或 assets/fonts/ 記得重跑：
##     python tools/gen_manifest.py
##
## 為什麼自動產生而不是手寫：README 說使用者可以自己丟音檔進
## audio/music/ 與 audio/sfx/。手寫清單在這種設計下必然腐化 ——
## 使用者加了新檔卻忘了更新，新檔在網頁版就會靜靜地不見。

## ── 音訊 ──
const A_MUSIC_DASH := preload("res://audio/music/dash.ogg")
const A_MUSIC_HIT := preload("res://audio/music/hit.ogg")
const A_MUSIC_HOSI := preload("res://audio/music/hosi.ogg")
const A_MUSIC_RYU := preload("res://audio/music/ryu.ogg")
const A_SFX_BACK := preload("res://audio/sfx/back.mp3")
const A_SFX_MISS := preload("res://audio/sfx/miss.mp3")
const A_SFX_SHATTER := preload("res://audio/sfx/shatter.mp3")
const A_SFX_SHIFT := preload("res://audio/sfx/shift.mp3")
const A_SFX_TAP := preload("res://audio/sfx/tap.mp3")
const A_SFX_TICK := preload("res://audio/sfx/tick.mp3")
const A_KANA_A := preload("res://audio/kana/a.mp3")
const A_KANA_BA := preload("res://audio/kana/ba.mp3")
const A_KANA_BE := preload("res://audio/kana/be.mp3")
const A_KANA_BI := preload("res://audio/kana/bi.mp3")
const A_KANA_BO := preload("res://audio/kana/bo.mp3")
const A_KANA_BU := preload("res://audio/kana/bu.mp3")
const A_KANA_BYA := preload("res://audio/kana/bya.mp3")
const A_KANA_BYO := preload("res://audio/kana/byo.mp3")
const A_KANA_BYU := preload("res://audio/kana/byu.mp3")
const A_KANA_CHA := preload("res://audio/kana/cha.mp3")
const A_KANA_CHI := preload("res://audio/kana/chi.mp3")
const A_KANA_CHO := preload("res://audio/kana/cho.mp3")
const A_KANA_CHU := preload("res://audio/kana/chu.mp3")
const A_KANA_DA := preload("res://audio/kana/da.mp3")
const A_KANA_DE := preload("res://audio/kana/de.mp3")
const A_KANA_DO := preload("res://audio/kana/do.mp3")
const A_KANA_E := preload("res://audio/kana/e.mp3")
const A_KANA_FU := preload("res://audio/kana/fu.mp3")
const A_KANA_GA := preload("res://audio/kana/ga.mp3")
const A_KANA_GE := preload("res://audio/kana/ge.mp3")
const A_KANA_GI := preload("res://audio/kana/gi.mp3")
const A_KANA_GO := preload("res://audio/kana/go.mp3")
const A_KANA_GU := preload("res://audio/kana/gu.mp3")
const A_KANA_GYA := preload("res://audio/kana/gya.mp3")
const A_KANA_GYO := preload("res://audio/kana/gyo.mp3")
const A_KANA_GYU := preload("res://audio/kana/gyu.mp3")
const A_KANA_HA := preload("res://audio/kana/ha.mp3")
const A_KANA_HE := preload("res://audio/kana/he.mp3")
const A_KANA_HI := preload("res://audio/kana/hi.mp3")
const A_KANA_HO := preload("res://audio/kana/ho.mp3")
const A_KANA_HYA := preload("res://audio/kana/hya.mp3")
const A_KANA_HYO := preload("res://audio/kana/hyo.mp3")
const A_KANA_HYU := preload("res://audio/kana/hyu.mp3")
const A_KANA_I := preload("res://audio/kana/i.mp3")
const A_KANA_JA := preload("res://audio/kana/ja.mp3")
const A_KANA_JI := preload("res://audio/kana/ji.mp3")
const A_KANA_JO := preload("res://audio/kana/jo.mp3")
const A_KANA_JU := preload("res://audio/kana/ju.mp3")
const A_KANA_KA := preload("res://audio/kana/ka.mp3")
const A_KANA_KE := preload("res://audio/kana/ke.mp3")
const A_KANA_KI := preload("res://audio/kana/ki.mp3")
const A_KANA_KO := preload("res://audio/kana/ko.mp3")
const A_KANA_KU := preload("res://audio/kana/ku.mp3")
const A_KANA_KYA := preload("res://audio/kana/kya.mp3")
const A_KANA_KYO := preload("res://audio/kana/kyo.mp3")
const A_KANA_KYU := preload("res://audio/kana/kyu.mp3")
const A_KANA_MA := preload("res://audio/kana/ma.mp3")
const A_KANA_ME := preload("res://audio/kana/me.mp3")
const A_KANA_MI := preload("res://audio/kana/mi.mp3")
const A_KANA_MO := preload("res://audio/kana/mo.mp3")
const A_KANA_MU := preload("res://audio/kana/mu.mp3")
const A_KANA_MYA := preload("res://audio/kana/mya.mp3")
const A_KANA_MYO := preload("res://audio/kana/myo.mp3")
const A_KANA_MYU := preload("res://audio/kana/myu.mp3")
const A_KANA_N := preload("res://audio/kana/n.mp3")
const A_KANA_NA := preload("res://audio/kana/na.mp3")
const A_KANA_NE := preload("res://audio/kana/ne.mp3")
const A_KANA_NI := preload("res://audio/kana/ni.mp3")
const A_KANA_NO := preload("res://audio/kana/no.mp3")
const A_KANA_NU := preload("res://audio/kana/nu.mp3")
const A_KANA_NYA := preload("res://audio/kana/nya.mp3")
const A_KANA_NYO := preload("res://audio/kana/nyo.mp3")
const A_KANA_NYU := preload("res://audio/kana/nyu.mp3")
const A_KANA_O := preload("res://audio/kana/o.mp3")
const A_KANA_PA := preload("res://audio/kana/pa.mp3")
const A_KANA_PE := preload("res://audio/kana/pe.mp3")
const A_KANA_PI := preload("res://audio/kana/pi.mp3")
const A_KANA_PO := preload("res://audio/kana/po.mp3")
const A_KANA_PU := preload("res://audio/kana/pu.mp3")
const A_KANA_PYA := preload("res://audio/kana/pya.mp3")
const A_KANA_PYO := preload("res://audio/kana/pyo.mp3")
const A_KANA_PYU := preload("res://audio/kana/pyu.mp3")
const A_KANA_RA := preload("res://audio/kana/ra.mp3")
const A_KANA_RE := preload("res://audio/kana/re.mp3")
const A_KANA_RI := preload("res://audio/kana/ri.mp3")
const A_KANA_RO := preload("res://audio/kana/ro.mp3")
const A_KANA_RU := preload("res://audio/kana/ru.mp3")
const A_KANA_RYA := preload("res://audio/kana/rya.mp3")
const A_KANA_RYO := preload("res://audio/kana/ryo.mp3")
const A_KANA_RYU := preload("res://audio/kana/ryu.mp3")
const A_KANA_SA := preload("res://audio/kana/sa.mp3")
const A_KANA_SE := preload("res://audio/kana/se.mp3")
const A_KANA_SHA := preload("res://audio/kana/sha.mp3")
const A_KANA_SHI := preload("res://audio/kana/shi.mp3")
const A_KANA_SHO := preload("res://audio/kana/sho.mp3")
const A_KANA_SHU := preload("res://audio/kana/shu.mp3")
const A_KANA_SO := preload("res://audio/kana/so.mp3")
const A_KANA_SU := preload("res://audio/kana/su.mp3")
const A_KANA_TA := preload("res://audio/kana/ta.mp3")
const A_KANA_TE := preload("res://audio/kana/te.mp3")
const A_KANA_TO := preload("res://audio/kana/to.mp3")
const A_KANA_TSU := preload("res://audio/kana/tsu.mp3")
const A_KANA_U := preload("res://audio/kana/u.mp3")
const A_KANA_WA := preload("res://audio/kana/wa.mp3")
const A_KANA_WO := preload("res://audio/kana/wo.mp3")
const A_KANA_YA := preload("res://audio/kana/ya.mp3")
const A_KANA_YO := preload("res://audio/kana/yo.mp3")
const A_KANA_YU := preload("res://audio/kana/yu.mp3")
const A_KANA_ZA := preload("res://audio/kana/za.mp3")
const A_KANA_ZE := preload("res://audio/kana/ze.mp3")
const A_KANA_ZO := preload("res://audio/kana/zo.mp3")
const A_KANA_ZU := preload("res://audio/kana/zu.mp3")

## ── 字型 ──
const F_BOLD := preload("res://assets/fonts/bold.ttf")
const F_DISPLAY := preload("res://assets/fonts/display.ttf")
const F_UI := preload("res://assets/fonts/ui.ttf")

## ── 分組清單 ──
## Sfx 與 Curriculum 讀這三個清單，取代 DirAccess 目錄掃描。

const MUSIC: Array = [
	{"name": "dash", "path": "res://audio/music/dash.ogg"},
	{"name": "hit", "path": "res://audio/music/hit.ogg"},
	{"name": "hosi", "path": "res://audio/music/hosi.ogg"},
	{"name": "ryu", "path": "res://audio/music/ryu.ogg"},
]

const SFX: Array = [
	{"name": "back", "path": "res://audio/sfx/back.mp3"},
	{"name": "miss", "path": "res://audio/sfx/miss.mp3"},
	{"name": "shatter", "path": "res://audio/sfx/shatter.mp3"},
	{"name": "shift", "path": "res://audio/sfx/shift.mp3"},
	{"name": "tap", "path": "res://audio/sfx/tap.mp3"},
	{"name": "tick", "path": "res://audio/sfx/tick.mp3"},
]

const KANA: Array = [
	{"name": "a", "path": "res://audio/kana/a.mp3"},
	{"name": "ba", "path": "res://audio/kana/ba.mp3"},
	{"name": "be", "path": "res://audio/kana/be.mp3"},
	{"name": "bi", "path": "res://audio/kana/bi.mp3"},
	{"name": "bo", "path": "res://audio/kana/bo.mp3"},
	{"name": "bu", "path": "res://audio/kana/bu.mp3"},
	{"name": "bya", "path": "res://audio/kana/bya.mp3"},
	{"name": "byo", "path": "res://audio/kana/byo.mp3"},
	{"name": "byu", "path": "res://audio/kana/byu.mp3"},
	{"name": "cha", "path": "res://audio/kana/cha.mp3"},
	{"name": "chi", "path": "res://audio/kana/chi.mp3"},
	{"name": "cho", "path": "res://audio/kana/cho.mp3"},
	{"name": "chu", "path": "res://audio/kana/chu.mp3"},
	{"name": "da", "path": "res://audio/kana/da.mp3"},
	{"name": "de", "path": "res://audio/kana/de.mp3"},
	{"name": "do", "path": "res://audio/kana/do.mp3"},
	{"name": "e", "path": "res://audio/kana/e.mp3"},
	{"name": "fu", "path": "res://audio/kana/fu.mp3"},
	{"name": "ga", "path": "res://audio/kana/ga.mp3"},
	{"name": "ge", "path": "res://audio/kana/ge.mp3"},
	{"name": "gi", "path": "res://audio/kana/gi.mp3"},
	{"name": "go", "path": "res://audio/kana/go.mp3"},
	{"name": "gu", "path": "res://audio/kana/gu.mp3"},
	{"name": "gya", "path": "res://audio/kana/gya.mp3"},
	{"name": "gyo", "path": "res://audio/kana/gyo.mp3"},
	{"name": "gyu", "path": "res://audio/kana/gyu.mp3"},
	{"name": "ha", "path": "res://audio/kana/ha.mp3"},
	{"name": "he", "path": "res://audio/kana/he.mp3"},
	{"name": "hi", "path": "res://audio/kana/hi.mp3"},
	{"name": "ho", "path": "res://audio/kana/ho.mp3"},
	{"name": "hya", "path": "res://audio/kana/hya.mp3"},
	{"name": "hyo", "path": "res://audio/kana/hyo.mp3"},
	{"name": "hyu", "path": "res://audio/kana/hyu.mp3"},
	{"name": "i", "path": "res://audio/kana/i.mp3"},
	{"name": "ja", "path": "res://audio/kana/ja.mp3"},
	{"name": "ji", "path": "res://audio/kana/ji.mp3"},
	{"name": "jo", "path": "res://audio/kana/jo.mp3"},
	{"name": "ju", "path": "res://audio/kana/ju.mp3"},
	{"name": "ka", "path": "res://audio/kana/ka.mp3"},
	{"name": "ke", "path": "res://audio/kana/ke.mp3"},
	{"name": "ki", "path": "res://audio/kana/ki.mp3"},
	{"name": "ko", "path": "res://audio/kana/ko.mp3"},
	{"name": "ku", "path": "res://audio/kana/ku.mp3"},
	{"name": "kya", "path": "res://audio/kana/kya.mp3"},
	{"name": "kyo", "path": "res://audio/kana/kyo.mp3"},
	{"name": "kyu", "path": "res://audio/kana/kyu.mp3"},
	{"name": "ma", "path": "res://audio/kana/ma.mp3"},
	{"name": "me", "path": "res://audio/kana/me.mp3"},
	{"name": "mi", "path": "res://audio/kana/mi.mp3"},
	{"name": "mo", "path": "res://audio/kana/mo.mp3"},
	{"name": "mu", "path": "res://audio/kana/mu.mp3"},
	{"name": "mya", "path": "res://audio/kana/mya.mp3"},
	{"name": "myo", "path": "res://audio/kana/myo.mp3"},
	{"name": "myu", "path": "res://audio/kana/myu.mp3"},
	{"name": "n", "path": "res://audio/kana/n.mp3"},
	{"name": "na", "path": "res://audio/kana/na.mp3"},
	{"name": "ne", "path": "res://audio/kana/ne.mp3"},
	{"name": "ni", "path": "res://audio/kana/ni.mp3"},
	{"name": "no", "path": "res://audio/kana/no.mp3"},
	{"name": "nu", "path": "res://audio/kana/nu.mp3"},
	{"name": "nya", "path": "res://audio/kana/nya.mp3"},
	{"name": "nyo", "path": "res://audio/kana/nyo.mp3"},
	{"name": "nyu", "path": "res://audio/kana/nyu.mp3"},
	{"name": "o", "path": "res://audio/kana/o.mp3"},
	{"name": "pa", "path": "res://audio/kana/pa.mp3"},
	{"name": "pe", "path": "res://audio/kana/pe.mp3"},
	{"name": "pi", "path": "res://audio/kana/pi.mp3"},
	{"name": "po", "path": "res://audio/kana/po.mp3"},
	{"name": "pu", "path": "res://audio/kana/pu.mp3"},
	{"name": "pya", "path": "res://audio/kana/pya.mp3"},
	{"name": "pyo", "path": "res://audio/kana/pyo.mp3"},
	{"name": "pyu", "path": "res://audio/kana/pyu.mp3"},
	{"name": "ra", "path": "res://audio/kana/ra.mp3"},
	{"name": "re", "path": "res://audio/kana/re.mp3"},
	{"name": "ri", "path": "res://audio/kana/ri.mp3"},
	{"name": "ro", "path": "res://audio/kana/ro.mp3"},
	{"name": "ru", "path": "res://audio/kana/ru.mp3"},
	{"name": "rya", "path": "res://audio/kana/rya.mp3"},
	{"name": "ryo", "path": "res://audio/kana/ryo.mp3"},
	{"name": "ryu", "path": "res://audio/kana/ryu.mp3"},
	{"name": "sa", "path": "res://audio/kana/sa.mp3"},
	{"name": "se", "path": "res://audio/kana/se.mp3"},
	{"name": "sha", "path": "res://audio/kana/sha.mp3"},
	{"name": "shi", "path": "res://audio/kana/shi.mp3"},
	{"name": "sho", "path": "res://audio/kana/sho.mp3"},
	{"name": "shu", "path": "res://audio/kana/shu.mp3"},
	{"name": "so", "path": "res://audio/kana/so.mp3"},
	{"name": "su", "path": "res://audio/kana/su.mp3"},
	{"name": "ta", "path": "res://audio/kana/ta.mp3"},
	{"name": "te", "path": "res://audio/kana/te.mp3"},
	{"name": "to", "path": "res://audio/kana/to.mp3"},
	{"name": "tsu", "path": "res://audio/kana/tsu.mp3"},
	{"name": "u", "path": "res://audio/kana/u.mp3"},
	{"name": "wa", "path": "res://audio/kana/wa.mp3"},
	{"name": "wo", "path": "res://audio/kana/wo.mp3"},
	{"name": "ya", "path": "res://audio/kana/ya.mp3"},
	{"name": "yo", "path": "res://audio/kana/yo.mp3"},
	{"name": "yu", "path": "res://audio/kana/yu.mp3"},
	{"name": "za", "path": "res://audio/kana/za.mp3"},
	{"name": "ze", "path": "res://audio/kana/ze.mp3"},
	{"name": "zo", "path": "res://audio/kana/zo.mp3"},
	{"name": "zu", "path": "res://audio/kana/zu.mp3"},
]

## 必須被 sfx.gd 讀取，否則資源分析器會丟棄以上所有相依關係。
const KEEPALIVE: Array = [
	A_MUSIC_DASH,
	A_MUSIC_HIT,
	A_MUSIC_HOSI,
	A_MUSIC_RYU,
	A_SFX_BACK,
	A_SFX_MISS,
	A_SFX_SHATTER,
	A_SFX_SHIFT,
	A_SFX_TAP,
	A_SFX_TICK,
	A_KANA_A,
	A_KANA_BA,
	A_KANA_BE,
	A_KANA_BI,
	A_KANA_BO,
	A_KANA_BU,
	A_KANA_BYA,
	A_KANA_BYO,
	A_KANA_BYU,
	A_KANA_CHA,
	A_KANA_CHI,
	A_KANA_CHO,
	A_KANA_CHU,
	A_KANA_DA,
	A_KANA_DE,
	A_KANA_DO,
	A_KANA_E,
	A_KANA_FU,
	A_KANA_GA,
	A_KANA_GE,
	A_KANA_GI,
	A_KANA_GO,
	A_KANA_GU,
	A_KANA_GYA,
	A_KANA_GYO,
	A_KANA_GYU,
	A_KANA_HA,
	A_KANA_HE,
	A_KANA_HI,
	A_KANA_HO,
	A_KANA_HYA,
	A_KANA_HYO,
	A_KANA_HYU,
	A_KANA_I,
	A_KANA_JA,
	A_KANA_JI,
	A_KANA_JO,
	A_KANA_JU,
	A_KANA_KA,
	A_KANA_KE,
	A_KANA_KI,
	A_KANA_KO,
	A_KANA_KU,
	A_KANA_KYA,
	A_KANA_KYO,
	A_KANA_KYU,
	A_KANA_MA,
	A_KANA_ME,
	A_KANA_MI,
	A_KANA_MO,
	A_KANA_MU,
	A_KANA_MYA,
	A_KANA_MYO,
	A_KANA_MYU,
	A_KANA_N,
	A_KANA_NA,
	A_KANA_NE,
	A_KANA_NI,
	A_KANA_NO,
	A_KANA_NU,
	A_KANA_NYA,
	A_KANA_NYO,
	A_KANA_NYU,
	A_KANA_O,
	A_KANA_PA,
	A_KANA_PE,
	A_KANA_PI,
	A_KANA_PO,
	A_KANA_PU,
	A_KANA_PYA,
	A_KANA_PYO,
	A_KANA_PYU,
	A_KANA_RA,
	A_KANA_RE,
	A_KANA_RI,
	A_KANA_RO,
	A_KANA_RU,
	A_KANA_RYA,
	A_KANA_RYO,
	A_KANA_RYU,
	A_KANA_SA,
	A_KANA_SE,
	A_KANA_SHA,
	A_KANA_SHI,
	A_KANA_SHO,
	A_KANA_SHU,
	A_KANA_SO,
	A_KANA_SU,
	A_KANA_TA,
	A_KANA_TE,
	A_KANA_TO,
	A_KANA_TSU,
	A_KANA_U,
	A_KANA_WA,
	A_KANA_WO,
	A_KANA_YA,
	A_KANA_YO,
	A_KANA_YU,
	A_KANA_ZA,
	A_KANA_ZE,
	A_KANA_ZO,
	A_KANA_ZU,
	F_BOLD,
	F_DISPLAY,
	F_UI,
]
