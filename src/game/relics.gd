extends RefCounted
class_name RelicPool

## 遺物（Roguelite 強化）資料表。
##
## 為什麼需要：同一套題庫，用不同的強化組合會是十幾種節奏。
## 這是「玩得久」的來源，也是後續更新與 DLC 的落點。

const LIST := [
	{
		"id": "muga", "name": "心眼", "icon": "眼",
		"desc": "石碑永遠清晰，不受距離影響。",
		"color": Color(0.55, 0.90, 1.0), "max": 1,
	},
	{
		"id": "tousei", "name": "透視", "icon": "眼",
		"desc": "石碑接近時，碑面下方浮出羅馬字。",
		"color": Color(0.62, 0.78, 1.0), "max": 1,
	},
	{
		"id": "taiwa", "name": "不倒翁", "icon": "盾",
		"desc": "體力上限 +40，答錯的懲罰減半。",
		"color": Color(0.45, 0.95, 0.72), "max": 2,
	},
	{
		"id": "juugo", "name": "重擊", "icon": "破",
		"desc": "撞碎石碑時額外產生衝擊波，答對的治療 +50%。",
		"color": Color(1.0, 0.66, 0.30), "max": 2,
	},
	{
		"id": "baigeki", "name": "倍率", "icon": "倍",
		"desc": "得分 ×1.55，但奔馳速度 +15%。",
		"color": Color(1.0, 0.82, 0.42), "max": 3,
	},
	{
		"id": "denpatsu", "name": "電走", "icon": "速",
		"desc": "答對時反應越快評價越高。這個讓拿到「PERFECT」的時間加長 45%。",
		"color": Color(0.85, 0.55, 1.0), "max": 2,
	},
	{
		"id": "minkyo", "name": "明鏡", "icon": "再",
		"desc": "答錯時立刻以同一題重新挑戰（不扣連段）。",
		"color": Color(0.95, 0.55, 0.80), "max": 1,
	},
	{
		"id": "sesshu", "name": "採集", "icon": "玉",
		"desc": "路上浮現詞彙寶石，撞到即收進單詞本。",
		"color": Color(0.55, 0.95, 0.85), "max": 1,
	},
	{
		"id": "jikyuu", "name": "持久", "icon": "力",
		"desc": "體力消耗 −35%。",
		"color": Color(0.70, 0.95, 0.55), "max": 2,
	},
	{
		"id": "mugen", "name": "無限", "icon": "連",
		"desc": "連段上限提高，倍率成長更快。",
		"color": Color(0.70, 0.60, 1.0), "max": 1,
	},
]

## 遺物的「當下真實數值」。
##
## 撿到遺物只給一張圖示，之後整局都看不出它在幹嘛，體感自然低。
## 讓 HUD 上的圖示帶著即時數字，玩家可以隨時確認自己正在受惠 ——
## 這比偷偷加強數值有用得多，因為玩家感覺得到的是「看見」。
static func status(id: String, n: int, ctx: Dictionary) -> String:
	match id:
		"muga":
			return "碑面全程清晰，不因距離變暗"
		"tousei":
			return "接近時碑面下方浮出羅馬字"
		"taiwa":
			return "體力上限 %d" % int(ctx.get("stamina_cap", 100))
		"juugo":
			return "每題回 %d 體力" % int(ctx.get("heal", 0))
		"baigeki":
			return "得分 ×%.2f　速度 +%d%%" % [
				float(ctx.get("mult", 1.0)), int(round(float(ctx.get("speed_bonus", 0.0)) * 100.0))]
		"denpatsu":
			return "Perfect 窗口 ±%dms" % int(ctx.get("perfect_ms", 0))
		"minkyo":
			return "答錯原地重試"
		"sesshu":
			return "已收集 %d 顆寶石" % int(ctx.get("gems", 0))
		"jikyuu":
			return "體力消耗 −%d%%" % int(round(float(ctx.get("drain_cut", 0.0)) * 100.0))
		"mugen":
			return "倍率上限 ×%.1f" % float(ctx.get("combo_top", 3.0))
	return ""


## 精簡版：遊戲中底欄空間有限，只放得下幾個字。
## 完整版留在暫停／結算畫面。
static func status_short(id: String, ctx: Dictionary) -> String:
	match id:
		"muga":
			return "清晰"
		"tousei":
			return "羅馬字"
		"taiwa":
			return "上限%d" % int(ctx.get("stamina_cap", 100))
		"juugo":
			return "回%d" % int(ctx.get("heal", 0))
		"baigeki":
			return "×%.2f" % float(ctx.get("mult", 1.0))
		"denpatsu":
			return "±%dms" % int(ctx.get("perfect_ms", 0))
		"minkyo":
			return "可重試"
		"sesshu":
			return "寶石%d" % int(ctx.get("gems", 0))
		"jikyuu":
			return "−%d%%" % int(round(float(ctx.get("drain_cut", 0.0)) * 100.0))
		"mugen":
			return "上限×%.1f" % float(ctx.get("combo_top", 3.0))
	return ""


static var _by_id: Dictionary = {}


static func get_def(id: String) -> Dictionary:
	if _by_id.is_empty():
		for r in LIST:
			_by_id[r["id"]] = r
	return _by_id.get(id, {})


## 依目前持有狀態抽三個互異的候選
static func roll(owned: Dictionary, rng := RandomNumberGenerator.new()) -> Array:
	get_def("muga")   # 順帶建立索引
	var pool: Array = []
	for r in LIST:
		var have := int(owned.get(r["id"], 0))
		if have < int(r["max"]):
			pool.append(r)
	pool.shuffle()
	var out: Array = []
	for r in pool:
		if out.size() >= 3:
			break
		out.append(r)
	return out


## 隨機挑選題庫以外的稀有詞彙，作為寶石獎勵
static func gem_word(rng: RandomNumberGenerator) -> Array:
	var with_words: Array = KanaDB.kana_with_word()
	if with_words.is_empty():
		return []
	var kana: String = with_words[rng.randi_range(0, with_words.size() - 1)]
	var w: Array = KanaDB.word_for(kana)
	if w.size() < 4:
		return []
	return [w[0], w[1], w[3]]
