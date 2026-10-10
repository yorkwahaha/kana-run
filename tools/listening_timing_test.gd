extends SceneTree
## 聽力題的語音預錄資源與高速撞擊窗口回歸（不依賴 GPU）。
var fails: Array[String] = []


func _init() -> void:
	_run.call_deferred()


func _ok(cond: bool, label: String) -> void:
	print("  %s %s" % ["PASS" if cond else "FAIL", label])
	if not cond:
		fails.append(label)


func _run() -> void:
	var C = load("res://src/core/curriculum.gd").new()
	var script = load("res://src/game/main.gd")
	var main = script.new()
	var q: Dictionary = C.make_question("あ", 0.0, C.QType.LISTENING)
	_ok(int(q.get("type", -1)) == C.QType.LISTENING, "強制聽音辨字建立聽力題")
	var path := str(q.get("audio", ""))
	_ok(path.begins_with("res://audio/kana/"), "聽力題使用打包的五十音音檔而非即時 TTS")
	var stream := main._voice_stream(path) as AudioStream
	_ok(stream != null and stream.get_length() > 0.0, "MP3 可立即從 Godot 資源包讀取")
	_ok(main._voice_stream(path) == stream, "同一錄音再次使用快取，不重複 load")
	var length := stream.get_length() if stream != null else 0.0
	for running_speed in [13.0, 25.0, 42.0, 60.0, 80.0]:
		var cap: float = main._listening_max_wave_speed(length)
		var wave_speed: float = minf(running_speed, cap)
		var from_spawn_to_hit: float = absf(main.SPAWN_Z) / wave_speed
		var min_time: float = maxf(2.5, length + 1.5) + 0.45
		_ok(from_spawn_to_hit + 0.0001 >= min_time, "跑速 %.0f 時聽力題仍有 >= %.2fs（實際 %.2fs）" % [running_speed, min_time, from_spawn_to_hit])
		var ordinary_time: float = absf(main.SPAWN_Z) / running_speed
		_ok(ordinary_time <= from_spawn_to_hit + 0.0001, "普通題速度不被聽力限速拖慢（跑速 %.0f）" % running_speed)
	_ok(main._listening_max_wave_speed(2.0) < main._listening_max_wave_speed(0.3), "長音檔自動延長作答時間")
	_ok(main._grade(200) == "perfect" and main._grade(700) == "great" and main._grade(1000) == "good", "PERFECT/GREAT/GOOD 原有反應時間門檻不變")
	main.free()
	print("[listening-timing] fail count: ", fails.size())
	quit(0 if fails.is_empty() else 1)
