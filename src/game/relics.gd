extends RefCounted
class_name RelicPool

## 這一局的打法牌。答對滿 10 題三選一，每張最多一張。
##
## 牌改的是這一輪怎麼跑：貪速度、換血、提早爆極限、保連段。
## 不放看答案、羅馬字、重試、收集單詞。那些會把題目變簡單，不會讓打法變不同。

const LIST := [
	{
		"id": "hayate", "name": "疾風", "icon": "風",
		"desc": "每 4 連，速度再快一截。連段一斷就回到原速。",
		"color": Color(0.45, 0.88, 1.0), "max": 1,
	},
	{
		"id": "teppeki", "name": "鐵壁", "icon": "盾",
		"desc": "體力上限 +30，答錯懲罰減半。得分變成 85%。",
		"color": Color(0.45, 0.95, 0.72), "max": 1,
	},
	{
		"id": "baigeki", "name": "倍率", "icon": "倍",
		"desc": "得分 ×1.6，速度 +12%。跑得更快，也更難看清。",
		"color": Color(1.0, 0.82, 0.42), "max": 1,
	},
	{
		"id": "bakuso", "name": "爆走", "icon": "爆",
		"desc": "熱度 5 點就進極限，極限多 2 秒。極限中體力掉更快。",
		"color": Color(1.0, 0.45, 0.32), "max": 1,
	},
	{
		"id": "zanshin", "name": "殘心", "icon": "殘",
		"desc": "答錯時連段減半，不歸零。倍率爬得比較慢。",
		"color": Color(0.70, 0.60, 1.0), "max": 1,
	},
	{
		"id": "issen", "name": "一閃", "icon": "閃",
		"desc": "PERFECT 分數 ×1.8。GOOD 只拿六成。",
		"color": Color(1.0, 0.92, 0.55), "max": 1,
	},
	{
		"id": "jikyuu", "name": "持久", "icon": "力",
		"desc": "體力消耗 −30%。極限的分數從 ×3 降成 ×2。",
		"color": Color(0.70, 0.95, 0.55), "max": 1,
	},
	{
		"id": "suberi", "name": "滑步", "icon": "步",
		"desc": "閃避不扣體力。閃過之後，下一題得分 ×1.5。",
		"color": Color(0.55, 0.78, 1.0), "max": 1,
	},
]


static func status(id: String, _n: int, ctx: Dictionary) -> String:
	match id:
		"hayate":
			return "速度 +%d%%" % int(ctx.get("hayate_pct", 0))
		"teppeki":
			return "體力上限 %d　得分 85%%" % int(ctx.get("stamina_cap", 100))
		"baigeki":
			return "得分 ×1.60　速度 +12%"
		"bakuso":
			return "熱度 %d 進極限" % int(ctx.get("od_need", 5))
		"zanshin":
			return "答錯連段減半"
		"issen":
			return "PERFECT ×1.8　GOOD ×0.6"
		"jikyuu":
			return "消耗 −30%　極限 ×2"
		"suberi":
			return "下一題 ×1.5" if bool(ctx.get("slip", false)) else "閃避不扣血"
	return ""


## 底欄只有幾個字。完整說明留在選牌畫面。
static func status_short(id: String, ctx: Dictionary) -> String:
	match id:
		"hayate":
			return "+%d%%" % int(ctx.get("hayate_pct", 0))
		"teppeki":
			return "85%"
		"baigeki":
			return "×1.6"
		"bakuso":
			return "熱%d" % int(ctx.get("od_need", 5))
		"zanshin":
			return "減半"
		"issen":
			return "×1.8"
		"jikyuu":
			return "−30%"
		"suberi":
			return "×1.5" if bool(ctx.get("slip", false)) else "免扣"
	return ""


static var _by_id: Dictionary = {}


static func get_def(id: String) -> Dictionary:
	if _by_id.is_empty():
		for r in LIST:
			_by_id[r["id"]] = r
	return _by_id.get(id, {})


## 依目前持有狀態抽三個互異的候選。已拿過的不再出現。
static func roll(owned: Dictionary, _rng := RandomNumberGenerator.new()) -> Array:
	get_def("hayate")
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
