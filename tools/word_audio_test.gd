extends SceneTree
## 單字題一定要有發音。
##
## 為什麼：單字題會顯示挖空的單詞（靴　○つ）與釋義。
## 不會念假名的人看到挖空根本無從選起，聽到整個單詞的讀音才能對照。
##
## 這個測試守住的是「凡是單字題，就一定有音檔」——
## 語音包只要少一個音，或詞庫讀音寫錯，覆蓋率就會掉下來。

var _fails: Array[String] = []


func _init() -> void:
	_run.call_deferred()


func _ok(cond: bool, what: String) -> void:
	if cond:
		print("  PASS  ", what)
	else:
		_fails.append(what)
		print("  FAIL  ", what)


func _run() -> void:
	var C = load("res://src/core/curriculum.gd").new()

	print("[word-audio] 語音包")
	_ok(C.listening_available(), "語音包可用")

	print("[word-audio] 拗音切分")
	# 逐字切會把 きゃ 變成 き + ゃ，後者查不到音檔
	var s := KanaDB.split_kana("きゃく")
	_ok(s.size() == 2 and str(s[0]) == "きゃ", "きゃく → [きゃ, く]（得到 %s）" % str(s))
	_ok(KanaDB.split_kana("びーる").size() == 2, "びーる → 跳過長音符（得到 %s）" % str(KanaDB.split_kana("びーる")))
	_ok(KanaDB.split_kana("みょう").size() == 2, "みょう → [みょ, う]（得到 %s）" % str(KanaDB.split_kana("みょう")))

	print("[word-audio] 詞庫讀音")
	# 讀音欄存成片假名會讓 reading.find(kana) 找不到，單字題整個消失
	for kana in ["ぱ", "ぴ", "ぷ", "ぺ", "ぽ"]:
		var w := KanaDB.word_for(kana)
		_ok(w.size() >= 4 and not KanaDB.is_katakana(str(w[1])),
			"%s 的讀音是平假名（%s）" % [kana, str(w[1]) if w.size() >= 4 else "無詞條"])

	print("[word-audio] 完整單詞錄音覆蓋")
	# 兩種來源必須分得很乾淨：有整詞錄音就「只有那一段」，
	# 沒有才整組退回逐音。混在一起會變成整詞後面又接一次逐音。
	var words_dir: String = (load("res://src/core/curriculum.gd") as GDScript).WORDS_DIR
	var full := 0
	var per_kana := 0
	var mixed: Array = []
	for kana in KanaDB.all_kana():
		var w = KanaDB.word_for(kana)
		if w.size() < 4:
			continue
		var clip: String = C.word_file(str(w[1]))
		if clip == "":
			continue
		full += 1
		_ok(clip.begins_with(words_dir), "%s 的整詞錄音在 %s 底下" % [kana, words_dir])
		var q: Dictionary = C.make_question(kana, 0.5, 1)
		# 讀音裡沒有這個假名時，題目會改成看羅馬字，本來就沒有單字音檔
		if int(q.get("type", -1)) != 1:
			continue
		var audio: Array = q.get("word_audio", [])
		if audio.size() != 1 or not str(audio[0]).begins_with(words_dir):
			mixed.append("%s(%s)" % [kana, str(audio)])
	print("    整詞錄音 %d 個" % full)
	_ok(mixed.is_empty(), "有整詞錄音時不混入逐音（混用：%s）" % str(mixed))

	print("[word-audio] word_file 邊界")
	_ok(C.word_file("") == "", "空讀音回傳空字串")
	var bogus: String = C.word_file("ヅズズookido")
	_ok(bogus == "" or str(bogus).begins_with(words_dir),
		"查不到的讀音回傳空字串（得到 %s）" % bogus)

	print("[word-audio] 覆蓋率")
	var blank_q := 0
	var with_audio := 0
	var missing: Array = []
	for kana in KanaDB.all_kana():
		var q: Dictionary = C.make_question(kana, 0.5, 1)   # 強制單字題
		if int(q.get("type", -1)) != 1:
			continue
		blank_q += 1
		var audio: Array = q.get("word_audio", [])
		if audio.size() == 1 and str(audio[0]).begins_with(words_dir):
			with_audio += 1
		else:
			missing.append("%s:%s" % [kana, str(audio)])
	print("    單字題 %d 題，整詞錄音 %d 題" % [blank_q, with_audio])
	_ok(missing.is_empty(), "每個單字題都只播一段整詞錄音（缺：%s）" % str(missing))

	print("[word-audio] 失敗 %d 項" % _fails.size())
	quit(0 if _fails.is_empty() else 1)
