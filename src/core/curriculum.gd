extends Node
## Curriculum — 題目生成器。
##
## 核心觀念：題目不能只是「羅馬字 → 假名」，那只會測出背圖表的能力。
## 隨進度逐步加入「挖空詞彙」「反向辨識」與「混淆決戰」，
## 把遊戲導向真正的閱讀訓練。

enum QType {
	ROMAJI,      ## 給羅馬字，選假名（原版核心）
	WORD_BLANK,  ## 給挖空的單詞 + 漢字 + 釋義，選假名
	KANA_READ,   ## 給假名，選羅馬字（反向）
	LISTENING,   ## 只給聲音，選假名（需外部音檔，預設關閉）
	BOSS,        ## 混淆決戰：干擾項全部來自易混淆群，答錯雙倍懲罰
}

const LISTENING_DIR := "res://audio/kana/"
const LISTENING_EXT := ["ogg", "mp3", "wav", "m4a"]

var script_mode := 0            ## 0 = 平假名, 1 = 片假名
var _listening_cache: Dictionary = {}


func _ready() -> void:
	script_mode = int(SaveGame.get_setting("katakana", 0))


func sync_settings() -> void:
	script_mode = int(SaveGame.get_setting("katakana", 0))


func listening_available() -> bool:
	# 匯出後的 pck 裡 DirAccess 常常報這個目錄不存在，
	# 但 manifest preload 進來的 mp3 還在。用資源是否存在當準。
	if ResourceLoader.exists(LISTENING_DIR + "a.mp3"):
		return true
	return DirAccess.dir_exists_absolute(LISTENING_DIR)


## 語音檔路徑。以假名的羅馬字命名（a.mp3 / kya.mp3 / shi.mp3 …）。
## 找不到就回空字串，題型會自動退回羅馬字題。
func listening_file(kana: String) -> String:
	if _listening_cache.has(kana):
		return str(_listening_cache[kana])
	var base := KanaDB.romaji(kana)
	var found := ""
	if listening_available():
		for ext in LISTENING_EXT:
			var path := "%s%s.%s" % [LISTENING_DIR, base, ext]
			if ResourceLoader.exists(path):
				found = path
				break
	_listening_cache[kana] = found
	return found


## 語音包涵蓋幾個音（給設定畫面顯示）
func listening_coverage() -> Dictionary:
	var ok := 0
	var total := 0
	for kana in KanaDB.all_kana():
		total += 1
		if listening_file(kana) != "":
			ok += 1
	return {"covered": ok, "total": total}


# ── 工具 ────────────────────────────────────────────────────────────────
## 把假名轉成目前選擇的平／片假名
func s(kana: String) -> String:
	return KanaDB.to_script(kana, script_mode == 1)


## 挑選干擾假名。優先同混淆群，數量不足時再從同單元補。
## 關鍵：必須排除「同音」假名（例如 を 與 お 都唸 o），
## 否則玩家讀音答對了卻被判錯，是最傷學習動機的缺陷。
func pick_distractors(target: String, count: int, same_unit: bool) -> Array:
	var out: Array = []
	var banned := homophones(target)
	banned.append(target)

	var near: Array = KanaDB.confusion(target)
	near.shuffle()
	for k in near:
		if out.size() >= count:
			break
		if not banned.has(k):
			out.append(k)
			banned.append(k)

	if out.size() < count:
		var pool: Array = []
		for kana in KanaDB.all_kana():
			if banned.has(kana):
				continue
			if not same_unit or KanaDB.kind_of(kana) == KanaDB.kind_of(target):
				pool.append(kana)
		pool.shuffle()
		for k in pool:
			if out.size() >= count:
				break
			out.append(k)
			banned.append(k)
	return out


## 找出與 target 羅馬字相同的所有假名（避免把同音當成干擾）
static func homophones(kana: String) -> Array:
	var r := KanaDB.romaji(kana)
	var out: Array = []
	for k in KanaDB.all_kana():
		if k != kana and KanaDB.romaji(k) == r:
			out.append(k)
	return out


## 反向題的干擾：同混淆群的羅馬字，去重並排除同音
func pick_romaji_distractors(target: String, count: int) -> Array:
	var r := KanaDB.romaji(target)
	var out: Array = []
	var seen := {r: true}
	for k in KanaDB.confusion(target):
		if out.size() >= count:
			break
		var rr: String = KanaDB.romaji(k)
		if rr != "" and not seen.has(rr):
			seen[rr] = true
			out.append(rr)
	if out.size() < count:
		for k in KanaDB.all_kana():
			if out.size() >= count:
				break
			var rr2: String = KanaDB.romaji(k)
			if rr2 != "" and not seen.has(rr2):
				seen[rr2] = true
				out.append(rr2)
	return out


# ── 主入口 ──────────────────────────────────────────────────────────────
## progress01 0..1：題目難度曲線
func make_question(kana: String, progress01: float, forced_type := -1) -> Dictionary:
	var type := forced_type
	if type < 0:
		type = _choose_type(kana, progress01)

	var q := {
		"type": type,
		"kana": kana,
		"romaji": KanaDB.romaji(kana),
		"choices": [],
		"target_index": 0,
		"choice_kind": "kana",
		"prompt": "",
		"prompt_sub": "",
		"word_kanji": "",
		"word_reading": "",
		"word_romaji": "",
		"word_meaning": "",
		"confusable_with": [],
		"hint": "",
	}

	match type:
		QType.KANA_READ:
			_build_kana_read(q, kana)
		QType.LISTENING:
			_build_listening(q, kana)
		QType.ROMAJI, QType.BOSS:
			_build_romaji(q, kana, type == QType.BOSS)
		_:
			_build_word_blank(q, kana)

	return q


func _choose_type(kana: String, progress01: float) -> int:
	if listening_available() and randf() < 0.14 and listening_file(kana) != "":
		return QType.LISTENING

	var has_word := KanaDB.has_word(kana)
	# 混淆決戰：每 10 題一次
	if progress01 > 0.12 and randf() < 0.10:
		return QType.BOSS

	# 詞彙挖空要等有詞條、且已經度過暖身期
	if has_word and progress01 > 0.18 and randf() < 0.42:
		return QType.WORD_BLANK

	# 反向辨識留到後半
	if progress01 > 0.45 and randf() < 0.32:
		return QType.KANA_READ

	return QType.ROMAJI


## 把候選打亂，並記錄正解落在第幾條跑道。
## 呼叫前需準備 q["choices"]（顯示字串）與 q["_sources"]（原始假名），正解固定在 index 0。
func _finalize(q: Dictionary) -> void:
	var displays: Array = q["choices"]
	var sources: Array = q["_sources"]
	var order: Array = []
	for i in displays.size():
		order.append(i)
	order.shuffle()

	var out_d: Array = []
	var out_s: Array = []
	var target_index := 0
	for new_i in order.size():
		var old_i: int = order[new_i]
		out_d.append(displays[old_i])
		out_s.append(sources[old_i])
		if old_i == 0:
			target_index = new_i

	q["choices"] = out_d
	q["choice_source"] = out_s
	q["target_index"] = target_index
	q.erase("_sources")


# ── 各題型 ──────────────────────────────────────────────────────────────
func _build_romaji(q: Dictionary, kana: String, boss: bool) -> void:
	var others: Array = pick_distractors(kana, 2, false)
	var trio: Array = [kana, others[0], others[1]]
	q["type"] = QType.BOSS if boss else QType.ROMAJI
	q["answer"] = kana
	q["choice_kind"] = "kana"
	q["choices"] = trio.map(func(k): return s(k))
	q["_sources"] = trio
	q["prompt"] = KanaDB.romaji(kana)
	q["prompt_sub"] = "混淆決戰 — 找出正確的假名" if boss else "讀出這個音"
	q["confusable_with"] = KanaDB.confusion(kana).slice(0, 3).map(func(k): return s(k))
	_finalize(q)


func _build_word_blank(q: Dictionary, kana: String) -> void:
	var w := KanaDB.word_for(kana)
	if w.size() < 4:
		_build_romaji(q, kana, false)
		return
	var kanji: String = w[0]
	var reading: String = w[1]
	var romaji_w: String = w[2]
	var meaning: String = w[3]

	var at := reading.find(kana)
	if at < 0:
		_build_romaji(q, kana, false)
		return

	var others: Array = pick_distractors(kana, 2, false)
	var trio: Array = [kana, others[0], others[1]]
	q["type"] = QType.WORD_BLANK
	q["answer"] = kana
	q["choice_kind"] = "kana"
	q["choices"] = trio.map(func(k): return s(k))
	q["_sources"] = trio
	q["prompt"] = s(reading.substr(0, at)) + "○" + s(reading.substr(at + kana.length()))
	q["prompt_sub"] = "%s · %s" % [kanji, meaning]
	q["word_kanji"] = kanji
	q["word_reading"] = s(reading)
	q["word_romaji"] = romaji_w
	q["word_meaning"] = meaning
	q["hint"] = "完整讀音：%s（%s）" % [s(reading), romaji_w]
	# 單字題只播整詞。逐音接起來聽起來像三個獨立的音，而且會把答案的音拆開來唸。
	var wf := word_file(reading)
	q["word_audio"] = [wf] if wf != "" else []
	_finalize(q)


## 詞彙的完整錄音。`audio/words/<平假名讀音>.mp3`，例如 りゆう.mp3。
## 單字題只認這一個檔，不再把五十音音檔接成一個詞。
const WORDS_DIR := "res://audio/words/"

func word_file(reading: String) -> String:
	if reading.is_empty():
		return ""
	for ext in LISTENING_EXT:
		var path := "%s%s.%s" % [WORDS_DIR, reading, ext]
		if ResourceLoader.exists(path):
			return path
	return ""


func _build_kana_read(q: Dictionary, kana: String) -> void:
	var others: Array = pick_romaji_distractors(kana, 2)
	var trio_r: Array = [KanaDB.romaji(kana), others[0], others[1]]
	var trio_k: Array = [kana, "", ""]
	q["type"] = QType.KANA_READ
	q["answer"] = KanaDB.romaji(kana)
	q["choice_kind"] = "romaji"
	q["choices"] = trio_r
	q["_sources"] = trio_k
	q["prompt"] = s(kana)
	q["prompt_sub"] = "這個假名怎麼唸？"
	q["hint"] = "例：%s" % _example_text(kana)
	_finalize(q)


func _build_listening(q: Dictionary, kana: String) -> void:
	var path := listening_file(kana)
	if path == "":
		_build_romaji(q, kana, false)
		return
	var others: Array = pick_distractors(kana, 2, false)
	var trio: Array = [kana, others[0], others[1]]
	q["type"] = QType.LISTENING
	q["answer"] = kana
	q["choice_kind"] = "kana"
	q["choices"] = trio.map(func(k): return s(k))
	q["_sources"] = trio
	q["prompt"] = "♪"
	q["prompt_sub"] = "聽音辨字"
	q["audio"] = path
	_finalize(q)


func _example_text(kana: String) -> String:
	var w := KanaDB.word_for(kana)
	if w.size() < 4:
		return s(kana)
	return "%s %s（%s）" % [w[0], s(w[1]), w[3]]


## 錯題回饋卡：把正解、構成拆解與例詞講清楚。
## show_confusions 預設 false —— 「容易混淆」那一行資訊量低又擋畫面。
func explain_card(q: Dictionary, show_confusions := false) -> Dictionary:
	var kana: String = q["kana"]
	var card := {
		"kana": s(kana),
		"romaji": KanaDB.romaji(kana),
		"lines": [],
		"confusions": [],
	}

	# 1. 例詞（有的話）
	var w := KanaDB.word_for(kana)
	if w.size() >= 4:
		card["lines"].append("%s　%s（%s）" % [w[0], s(w[1]), w[3]])

	# 2. 構成拆解：濁點從哪來、拗音怎麼拼
	for line in KanaDB.decompose(kana):
		card["lines"].append(line)

	# 3. 同音假名
	var homo := homophones(kana)
	if not homo.is_empty():
		card["lines"].append("同音：%s（%s）" % [
			"、".join(homo.map(func(k): return s(k))),
			KanaDB.romaji(kana),
		])

	# 4. 五十音圖的左右鄰居 —— 沒有詞條的拗音靠這行也有東西可看
	if card["lines"].is_empty():
		var nb := KanaDB.neighbours(kana)
		if not nb.is_empty():
			card["lines"].append("五十音圖上它位於 %s 與 %s 之間" % [s(nb[0]), s(nb[1])])
		else:
			card["lines"].append("%s 讀作 %s" % [s(kana), KanaDB.romaji(kana)])

	# 混淆對照是選填的。太多資訊反而擋住畫面，預設不顯示。
	if show_confusions:
		for c in KanaDB.confusion(kana).slice(0, 3):
			card["confusions"].append("%s %s" % [s(c), KanaDB.romaji(c)])
	return card
