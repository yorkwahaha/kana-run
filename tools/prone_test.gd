extends SceneTree
## 倒地姿勢的接地檢查。
##
## 問題：被撞飛之後「身體的一半沉到地板下」。
## 與其靠肉眼猜角度，這裡直接量所有可見網格在角色本地空間的最低點，
## 確認整具身體都在 y >= 0 之上（也就是沒有穿進路面）。

var _fails: Array[String] = []


func _ok(cond: bool, what: String) -> void:
	if cond:
		print("  PASS  ", what)
	else:
		_fails.append(what)
		print("  FAIL  ", what)


func _init() -> void:
	_run.call_deferred()


## 遞迴收集所有 MeshInstance3D 的世界座標 AABB，取最低點
func _lowest(r: Node, acc: Array) -> void:
	if r is MeshInstance3D:
		var mi := r as MeshInstance3D
		if not mi.visible or mi.mesh == null:
			return
		var m := mi.global_transform * mi.get_aabb()
		acc.append(m.position.y)
	for c in r.get_children():
		_lowest(c, acc)


func _run() -> void:
	var runner := load("res://src/game/runner.gd").new() as Node3D
	get_root().add_child(runner)
	# 站在跑道平面 y=0 上，scale 已含在節點上
	runner.position = Vector3.ZERO
	await process_frame
	# 地面高度：跑道表面在 y=0
	var GROUND := 0.0

	print("[prone-test] 姿勢接地檢查")
	runner.reset()
	await process_frame
	var acc: Array = []
	_lowest(runner, acc)
	var lo: float = acc[0]
	for v in acc:
		lo = minf(lo, v)
	print("    站立最低點 %.3f" % lo)

	# 跪坐
	runner.collapse(false)
	for i in 240:
		await process_frame
	acc.clear()
	_lowest(runner, acc)
	lo = acc[0]
	for v in acc:
		lo = minf(lo, v)
	print("    跪坐最低點 %.3f  ground_fix=%.3f  collapse=%.3f  on=%s" % [lo, runner.get("_ground_fix"), runner.get("_collapse"), str(runner.get("_collapse_on"))])
	_ok(lo >= GROUND - 0.02, "跪坐沒有沉進地板（%.3f）" % lo)

	# 被撞飛趴地
	runner.reset()
	await process_frame
	runner.collapse(true)
	for i in 300:
		await process_frame
	acc.clear()
	_lowest(runner, acc)
	lo = acc[0]
	for v in acc:
		lo = minf(lo, v)
	print("    趴地最低點 %.3f" % lo)
	_ok(lo >= GROUND - 0.02, "趴地沒有沉進地板（%.3f）" % lo)
	_ok(lo <= GROUND + 0.35, "趴地確實貼著地板而不是浮空（%.3f）" % lo)

	print("[prone-test] 失敗 %d 項" % _fails.size())
	quit(0 if _fails.is_empty() else 1)
