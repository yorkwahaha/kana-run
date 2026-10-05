extends Node
## Srs — 適性化間隔重複引擎（本專案的真正護城河）。
##
## 兩條排題路線：
##   1. 新音依五十音圖順序出場（教學順序，不可跳）
##   2. 舊音依「弱度 × 遺忘天數 × 反應遲鈍」加權複習
## 因此第一局像課程、第三局之後像個人化教練。

const HISTORY_LEN := 16
const DAY := 86400.0
const WEAK_THRESHOLD := 0.72      ## 低於此正確率視為弱項
const SLOW_MULTIPLIER := 1.6      ## 反應時間的加權倍率
const DUE_HALFLIFE := 6.0         ## 天數遺忘曲線半衰期
const RUN_BEATS := 42             ## 一輪的題數。三到四分鐘，打完就結束
const NEW_PER_RUN := 8            ## 老玩家一輪裡最多塞幾個還沒見過的音

var session_correct := 0
var session_wrong := 0
var session_dodged := 0
var session_new := 0

var unit_kinds: Array = []
var _index := 0
var _queue: Array = []
var _new_pool: Array = []
var _review_pool: Array = []
var _session_ids: Array = []      ## 本局已出現的 kana，避免重複


## 產生本局的完整出題順序：
##   新音依五十音圖順序（教學順序不可跳），複習音依「弱度 × 遺忘 × 遲鈍」加權。
## 第一局像課程，之後每局都像個人化教練。
## beats < 0 用標準輪的題數。驟死把時鐘當終點，題列要長過 90 秒。
func build_queue(kinds: Array, beats := -1) -> Array:
	unit_kinds = kinds.duplicate()
	_index = 0
	_queue = []
	_new_pool = []
	_review_pool = []
	_session_ids = []
	session_correct = 0
	session_wrong = 0
	session_dodged = 0
	session_new = 0

	var unlocked := int(SaveGame.get_setting("unlock_all", 0)) == 1
	for kind in unit_kinds:
		for entry in KanaDB.unit(kind):
			var kana: String = entry[0]
			if unlocked or int(SaveGame.kana_record(kana).get("seen", 0)) == 0:
				_new_pool.append(kana)
			else:
				_review_pool.append(kana)

	_assemble_run(RUN_BEATS if beats < 0 else beats)
	return _queue.duplicate()


## 一輪固定長度，不把整本五十音一次跑完。
## 全是新音時照圖表順序取，單元太短就再繞一圈。
## 已經有複習池時，先放幾個新音，剩下用弱項加權抽，避免同一音連著出現。
func _assemble_run(limit: int) -> void:
	_queue = []
	if limit <= 0 or (_new_pool.is_empty() and _review_pool.is_empty()):
		return
	if _review_pool.is_empty():
		var i := 0
		while _queue.size() < limit:
			_queue.append(_new_pool[i % _new_pool.size()])
			i += 1
		return
	var fresh := mini(NEW_PER_RUN, _new_pool.size())
	for i in fresh:
		_queue.append(_new_pool[i])
	var guard := 0
	while _queue.size() < limit and guard < limit * 4:
		guard += 1
		var prev := "" if _queue.is_empty() else str(_queue[_queue.size() - 1])
		_queue.append(_pick_review(prev))


func _pick_review(avoid: String) -> String:
	if _review_pool.size() == 1:
		return str(_review_pool[0])
	# 指數權重會把最弱的幾個音放大到幾百倍，一局複習區只剩 3～5 個字在轉。
	# 線性權重仍讓弱項先出，最近四題再壓低，避免同一小圈無限輪迴。
	var recent := {}
	var start := maxi(0, _queue.size() - 4)
	for i in range(start, _queue.size()):
		recent[str(_queue[i])] = true
	var total := 0.0
	var weights: Array = []
	for k in _review_pool:
		var w := 1.0 + _urgency(str(k)) * 0.40
		if str(k) == avoid:
			w *= 0.05
		elif recent.has(str(k)):
			w *= 0.25
		total += w
		weights.append(total)
	var roll := randf() * maxf(total, 0.0001)
	var idx := 0
	while idx < weights.size() - 1 and roll > float(weights[idx]):
		idx += 1
	return str(_review_pool[idx])


func done() -> int:
	return _index


func total_count() -> int:
	return _queue.size()


func progress() -> float:
	return 0.0 if _queue.is_empty() else float(_index) / float(_queue.size())


func finished() -> bool:
	return _index >= _queue.size()


## 取下一題的目標假名；空了代表本局結束
func pop_next() -> String:
	if finished():
		return ""
	var kana: String = _queue[_index]
	_index += 1
	_session_ids.append(kana)
	return kana


## 閃避或自動重練：撤掉剛剛抽出的這一格，插回三題之後。
## 直接覆寫原格的話，下一題就是同一個音，棄題變成免費重考。
func requeue(kana: String) -> void:
	_index = maxi(0, _index - 1)
	if _index < _queue.size() and str(_queue[_index]) == kana:
		_queue.remove_at(_index)
	var at := mini(_index + 3, _queue.size())
	_queue.insert(at, kana)


func _record_of(kana: String) -> Dictionary:
	return SaveGame.kana_record(kana)


func day_now() -> int:
	return int(Time.get_unix_time_from_system() / DAY)


## 0..1：掌握度。用「正確率 × 連續答對 × 速度」合成
func mastery(kana: String) -> float:
	var r := _record_of(kana)
	var seen := int(r.get("seen", 0))
	if seen <= 0:
		return 0.0
	var acc := float(r.get("correct", 0)) / float(seen)
	var streak_bonus := clampf(float(r.get("streak", 0)) / 6.0, 0.0, 1.0)
	var avg := float(r.get("total_ms", 0)) / maxf(float(r.get("correct", 0)), 1.0)
	var speed := 1.0 if avg <= 0.0 else clampf(remap(avg, 400.0, 2600.0, 1.0, 0.0), 0.0, 1.0)
	var base := 0.55 * acc + 0.30 * streak_bonus + 0.15 * speed
	# 見過越多，權重越實在
	return clampf(base * clampf(0.65 + 0.35 * (float(seen) / 8.0), 0.0, 1.0), 0.0, 1.0)


func accuracy(kana: String) -> float:
	var r := _record_of(kana)
	var seen := int(r.get("seen", 0))
	if seen <= 0:
		return 1.0
	return float(r.get("correct", 0)) / float(seen)


func avg_ms(kana: String) -> float:
	var r := _record_of(kana)
	return float(r.get("total_ms", 0)) / maxf(float(r.get("correct", 0)), 1.0)


## 越急越優先
func _urgency(kana: String) -> float:
	var r := _record_of(kana)
	var seen := int(r.get("seen", 0))
	if seen <= 0:
		return 100.0

	var wrong_rate := 1.0 - float(r.get("correct", 0)) / float(seen)
	var weakness := 1.0
	if accuracy(kana) < WEAK_THRESHOLD:
		weakness = 1.0 + (WEAK_THRESHOLD - accuracy(kana)) * 2.4

	var last := int(r.get("last_day", -1))
	var days := maxf(0.0, float(day_now() - last))
	var due := 1.0 - pow(0.5, days / DUE_HALFLIFE)

	var a := avg_ms(kana)
	var speed_pen := 1.0
	if a > 0.0:
		speed_pen = 1.0 + clampf((a - 900.0) / 1400.0, 0.0, 1.0) * SLOW_MULTIPLIER

	return (0.35 + wrong_rate * 1.6) * weakness * (0.4 + due * 1.8) * speed_pen


## 已作答數（含答錯與閃避）
func answered_this_run() -> int:
	return session_correct + session_wrong + session_dodged


func is_review(kana: String) -> bool:
	return int(_record_of(kana).get("seen", 0)) > 0


# ── 紀錄一次作答 ────────────────────────────────────────────────────────
## verdict: 0 = 答錯, 1 = 答對, 2 = 閃避
func record(kana: String, verdict: int, reaction_ms: float) -> void:
	var r := _record_of(kana)
	r["seen"] = int(r.get("seen", 0)) + 1
	r["last_day"] = day_now()

	var hist: Array = r.get("history", [])
	hist.append(verdict)
	while hist.size() > HISTORY_LEN:
		hist.pop_front()
	r["history"] = hist

	match verdict:
		1:
			session_correct += 1
			r["correct"] = int(r.get("correct", 0)) + 1
			r["streak"] = int(r.get("streak", 0)) + 1
			r["total_ms"] = float(r.get("total_ms", 0.0)) + maxf(50.0, reaction_ms)
			var best := float(r.get("best_ms", 0.0))
			if best <= 0.0 or reaction_ms < best:
				r["best_ms"] = reaction_ms
			# ease 上升，但很慢，避免虛高
			r["ease"] = minf(3.2, float(r.get("ease", 2.5)) + 0.07)
		2:
			session_dodged += 1
			r["dodged"] = int(r.get("dodged", 0)) + 1
		_:
			session_wrong += 1
			r["wrong"] = int(r.get("wrong", 0)) + 1
			r["streak"] = 0
			r["ease"] = maxf(1.3, float(r.get("ease", 2.5)) - 0.45)

	SaveGame.mark_dirty()
	SaveGame.bump_total("answered")
	if verdict == 1:
		SaveGame.bump_total("correct")


# ── 結算報表 ────────────────────────────────────────────────────────────
## 依「最需要複習」排序取前 n 個
func weakest(n: int, only_answered := true) -> Array:
	var list: Array = []
	for kana in KanaDB.all_kana():
		if only_answered and int(_record_of(kana).get("seen", 0)) == 0:
			continue
		list.append(kana)
	list.sort_custom(func(a, b): return _urgency(b) > _urgency(a))
	return list.slice(0, mini(n, list.size()))


func slowest(n: int, only_answered := true) -> Array:
	var list: Array = []
	for kana in KanaDB.all_kana():
		if only_answered and int(_record_of(kana).get("correct", 0)) == 0:
			continue
		list.append(kana)
	list.sort_custom(func(a, b): return avg_ms(b) > avg_ms(a))
	return list.slice(0, mini(n, list.size()))


## 單元整體掌握度 0..1
func unit_mastery(kinds: Array) -> float:
	var total := 0.0
	var n := 0
	for kind in kinds:
		for entry in KanaDB.unit(kind):
			total += mastery(entry[0])
			n += 1
	return 0.0 if n == 0 else total / float(n)


func answered_count() -> int:
	return SaveGame.total("answered")
