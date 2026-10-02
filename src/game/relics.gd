extends RefCounted
class_name RelicPool

## 這一局的打法牌。答對滿 10 題三選一，每張最多一張。
##
## 牌改的是這一輪怎麼跑：貪速度、換血、提早爆極限、保連段。
## 不放看答案、羅馬字、重試、收集單詞。那些會把題目變簡單，不會讓打法變不同。

const LIST := [
	{
		"id": "hayate", "name": "疾風", "icon": "風",
		"type": "速度", "desc": "每 4 次連續答對立刻 +12 km/h，伴隨疾風提示。",
		"color": Color(0.45, 0.88, 1.0), "max": 1,
	},
	{
		"id": "teppeki", "name": "鐵壁", "icon": "盾",
		"type": "生存", "desc": "體力上限 +30，答錯扣血與前兩次失速都減半。",
		"color": Color(0.45, 0.95, 0.72), "max": 1,
	},
	{
		"id": "baigeki", "name": "倍率", "icon": "倍",
		"type": "速度", "desc": "得分 ×1.35；GREAT / PERFECT 再多加速，但答錯失速也更重。",
		"color": Color(1.0, 0.82, 0.42), "max": 1,
	},
	{
		"id": "bakuso", "name": "爆走", "icon": "爆",
		"type": "速度", "desc": "熱度 5 點就爆發極限，極限多 2 秒；期間更快、更耗體力。",
		"color": Color(1.0, 0.45, 0.32), "max": 1,
	},
	{
		"id": "zanshin", "name": "殘心", "icon": "殘",
		"type": "技巧", "desc": "先給一層保險；下一次答錯不增加連錯，且只小幅失速。每 6 次答對充回。",
		"color": Color(0.70, 0.60, 1.0), "max": 1,
	},
	{
		"id": "issen", "name": "一閃", "icon": "閃",
		"type": "技巧", "desc": "PERFECT 額外 +10 km/h 並放大撞擊回饋；分數 ×1.5。",
		"color": Color(1.0, 0.92, 0.55), "max": 1,
	},
	{
		"id": "jikyuu", "name": "持久", "icon": "力",
		"type": "生存", "desc": "奔跑耗體力 −15%；每 5 次答對再回復 15 體力。",
		"color": Color(0.70, 0.95, 0.55), "max": 1,
	},
	{
		"id": "suberi", "name": "滑步", "icon": "步",
		"type": "技巧", "desc": "閃避不扣體力並立刻 +15 km/h；下一題得分 ×1.5。",
		"color": Color(0.55, 0.78, 1.0), "max": 1,
	},
]


static func status(id: String, _n: int, ctx: Dictionary) -> String:
	match id:
		"hayate":
			return "每 4 連 +12 km/h"
		"teppeki":
			return "體力上限 %d　失速減半" % int(ctx.get("stamina_cap", 100))
		"baigeki":
			return "得分 ×1.35　高評價多加速"
		"bakuso":
			return "熱度 %d 進極限" % int(ctx.get("od_need", 5))
		"zanshin":
			return "保險 %s" % ("就緒" if bool(ctx.get("zanshin_ready", false)) else "充能中")
		"issen":
			return "PERFECT ×1.5　+10 km/h"
		"jikyuu":
			return "消耗 −15%　5 答回 15"
		"suberi":
			return "下一題 ×1.5" if bool(ctx.get("slip", false)) else "閃避 +15 km/h"
	return ""


## 底欄只有幾個字。完整說明留在選牌畫面。
static func status_short(id: String, ctx: Dictionary) -> String:
	match id:
		"hayate":
			return "4連+12"
		"teppeki":
			return "半傷"
		"baigeki":
			return "×1.35"
		"bakuso":
			return "熱%d" % int(ctx.get("od_need", 5))
		"zanshin":
			return "就緒" if bool(ctx.get("zanshin_ready", false)) else "充能"
		"issen":
			return "+10"
		"jikyuu":
			return "5答回血"
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
	for kind in ["速度", "生存", "技巧"]:
		for r in pool:
			if str(r.get("type", "")) == kind and r not in out:
				out.append(r)
				break
	for r in pool:
		if out.size() >= 3:
			break
		if r not in out:
			out.append(r)
	out.shuffle()
	return out
