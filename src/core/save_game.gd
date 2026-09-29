extends Node
## SaveGame — 設定與學習進度的持久化層。
##
## 一切資料放在 user:// 下的 JSON。寫入採「先寫暫存檔再替換」，
## 避免中途中斷（例如在手機上被系統殺掉）造成存檔損毀。

const SAVE_PATH := "user://kana_run_save.json"
const TMP_PATH := "user://kana_run_save.tmp"
const AUTOSAVE_DEBOUNCE := 1.2

const DEFAULT_SETTINGS := {
	"master_volume": 0.9,
	"sfx_volume": 0.9,
	"music_volume": 0.38,
	"screen_shake": 1.0,
	"reduce_motion": 0.0,   # 0 = 正常, 1 = 減少閃爍/震動
	"quality": 1,            # 0 = 流暢, 1 = 平衡, 2 = 精細
	"katakana": 0,           # 0 = 平假名, 1 = 片假名
	"show_romaji": 1,
	"unlock_all": 0,
}

var settings: Dictionary = {}
var data: Dictionary = {}

var _dirty := false
var _timer := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	settings = DEFAULT_SETTINGS.duplicate(true)
	data = {"kana": {}, "best": {}, "collection": {}, "totals": {}}
	load_all()


func load_all() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var text := FileAccess.get_file_as_string(SAVE_PATH)
	if text.is_empty():
		return
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("SaveGame: 存檔格式損毀，已忽略。")
		return
	var root: Dictionary = parsed
	if root.has("settings") and typeof(root["settings"]) == TYPE_DICTIONARY:
		for k in (root["settings"] as Dictionary).keys():
			if settings.has(k):
				settings[k] = root["settings"][k]
	if root.has("data") and typeof(root["data"]) == TYPE_DICTIONARY:
		for k in (root["data"] as Dictionary).keys():
			data[k] = root["data"][k]


func mark_dirty() -> void:
	_dirty = true


func _process(delta: float) -> void:
	if not _dirty:
		return
	_timer += delta
	if _timer >= AUTOSAVE_DEBOUNCE:
		flush()


func flush() -> void:
	_dirty = false
	_timer = 0.0
	var payload := {"version": 1, "settings": settings, "data": data}
	var f := FileAccess.open(TMP_PATH, FileAccess.WRITE)
	if f == null:
		push_warning("SaveGame: 無法寫入暫存檔 %s" % TMP_PATH)
		return
	f.store_string(JSON.stringify(payload))
	f.close()
	var da := DirAccess.open("user://")
	if da != null:
		da.remove(SAVE_PATH)
		da.rename(TMP_PATH, SAVE_PATH)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_APPLICATION_PAUSED:
		flush()


func get_setting(key: String, fallback: Variant = null) -> Variant:
	return settings.get(key, DEFAULT_SETTINGS.get(key, fallback))


func set_setting(key: String, value: Variant) -> void:
	settings[key] = value
	mark_dirty()


# ── 便捷存取 ────────────────────────────────────────────────────────────

func kana_record(kana: String) -> Dictionary:
	if not data["kana"].has(kana):
		data["kana"][kana] = {
			"seen": 0, "correct": 0, "wrong": 0, "dodged": 0,
			"total_ms": 0, "best_ms": 0, "streak": 0,
			"ease": 2.5, "last_day": -1, "history": [],
		}
	return data["kana"][kana]


func best_score(unit_key: String) -> int:
	return int(data["best"].get(unit_key, 0))


func set_best_score(unit_key: String, value: int) -> void:
	if value > best_score(unit_key):
		data["best"][unit_key] = value
		mark_dirty()


func collect_word(word: String) -> bool:
	if data["collection"].has(word):
		return false
	data["collection"][word] = Time.get_unix_time_from_system()
	mark_dirty()
	return true


func collected() -> int:
	return (data["collection"] as Dictionary).size()


func bump_total(field: String, amount: int = 1) -> void:
	var t: Dictionary = data["totals"]
	t[field] = int(t.get(field, 0)) + amount
	mark_dirty()


func total(field: String) -> int:
	return int((data["totals"] as Dictionary).get(field, 0))


func wipe_progress() -> void:
	data = {"kana": {}, "best": {}, "collection": {}, "totals": {}}
	mark_dirty()
	flush()
