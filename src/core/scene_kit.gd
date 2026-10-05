extends Node
## SceneKit — 程序化資產工廠。
##
## 專案內沒有任何 .glb / .png。所有幾何、材質、環境、天空、角色
## 都在執行期由程式生成，因此 clone 下來就能跑，也沒有授權負擔。

const SHADER_ROAD := "res://src/shaders/road.gdshader"
const SHADER_STONE := "res://src/shaders/stone.gdshader"
const SHADER_POST := "res://src/shaders/post_fx.gdshader"
const SHADER_BLOB := "res://src/shaders/blob.gdshader"
const SHADER_DISC := "res://src/shaders/disc.gdshader"

# 美術定調：夜藍 × 琥珀燈 × 品紅霓光
const COL_SKY_TOP := Color(0.035, 0.030, 0.085)
const COL_SKY_HORIZON := Color(0.34, 0.20, 0.44)
const COL_SKY_GROUND := Color(0.045, 0.038, 0.070)
const COL_SUN := Color(1.0, 0.86, 0.72)
const COL_KEY := Color(0.72, 0.80, 1.0)
const COL_FILL := Color(1.0, 0.52, 0.72)
const COL_LANTERN := Color(1.0, 0.68, 0.32)
const COL_INLAY := Color(1.0, 0.91, 0.74)

var _mesh_cache: Dictionary = {}
var _mat_cache: Dictionary = {}
var _shader_cache: Dictionary = {}
static var _radial_cache: Dictionary = {}


func _ready() -> void:
	# 提早載入 shader，避免第一次生成材質時卡頓
	_shader(SHADER_ROAD)
	_shader(SHADER_STONE)
	_shader(SHADER_POST)
	_shader(SHADER_BLOB)
	_shader(SHADER_DISC)


func _shader(path: String) -> Shader:
	if _shader_cache.has(path):
		return _shader_cache[path]
	var s: Shader = load(path)
	_shader_cache[path] = s
	return s


# ── 幾何 ────────────────────────────────────────────────────────────────
## 倒角盒：44 個三角面。倒角帶來的兩條高光稜線是「有 3D 資產」
## 與「只有一個 BoxMesh」最明顯的差別。
func chamfer_box(size: Vector3, chamfer := 0.06) -> ArrayMesh:
	var key := "cb_%.3f_%.3f_%.3f_%.3f" % [size.x, size.y, size.z, chamfer]
	if _mesh_cache.has(key):
		return _mesh_cache[key]

	var h := size * 0.5
	var c := clampf(chamfer, 0.001, minf(h.x, minf(h.y, h.z)) * 0.48)

	# 頂點表：key = (sx, sy, sz, face_axis)
	var verts := {}
	for sx in [-1, 1]:
		for sy in [-1, 1]:
			for sz in [-1, 1]:
				var s := [sx, sy, sz]
				for axis in 3:
					var v := Vector3(h.x * sx, h.y * sy, h.z * sz)
					for a in 3:
						if a != axis:
							v[a] -= c * float(s[a])
					verts[Vector4i(sx, sy, sz, axis)] = v

	var polys: Array = []

	# 六個主面
	for axis in 3:
		var others: Array = []
		for a in 3:
			if a != axis:
				others.append(a)
		for sign_v in [1, -1]:
			var quad: Array = []
			for combo in [[1, 1], [-1, 1], [-1, -1], [1, -1]]:
				var s := [0, 0, 0]
				s[axis] = sign_v
				s[others[0]] = combo[0]
				s[others[1]] = combo[1]
				quad.append(Vector4i(s[0], s[1], s[2], axis))
			polys.append(quad)

	# 十二條稜線倒角
	for a in 3:
		for b in range(a + 1, 3):
			var c_axis := 3 - a - b
			for sa in [1, -1]:
				for sb in [1, -1]:
					var quad2: Array = []
					for end_v in [-1, 1]:
						var s0 := [0, 0, 0]
						var s1 := [0, 0, 0]
						s0[a] = sa
						s0[b] = sb
						s0[c_axis] = end_v
						s1[a] = sa
						s1[b] = sb
						s1[c_axis] = -end_v
						quad2.append(Vector4i(s0[0], s0[1], s0[2], a))
						quad2.append(Vector4i(s1[0], s1[1], s1[2], a))
						quad2.append(Vector4i(s1[0], s1[1], s1[2], b))
						quad2.append(Vector4i(s0[0], s0[1], s0[2], b))
					polys.append(quad2)

	# 八個轉角
	for sx in [-1, 1]:
		for sy in [-1, 1]:
			for sz in [-1, 1]:
				polys.append([Vector4i(sx, sy, sz, 0), Vector4i(sx, sy, sz, 1), Vector4i(sx, sy, sz, 2)])

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	var out_v := PackedVector3Array()
	var out_n := PackedVector3Array()
	var out_uv := PackedVector2Array()

	for poly in polys:
		var pts: Array = []
		for vi in poly:
			pts.append(verts[vi] as Vector3)
		# 統一繞序：法線必須背向原點
		var p0: Vector3 = pts[0]
		var p1: Vector3 = pts[1]
		var p2: Vector3 = pts[2]
		var nrm: Vector3 = (p1 - p0).cross(p2 - p0).normalized()
		var centroid := Vector3.ZERO
		for p in pts:
			centroid += p
		centroid /= float(pts.size())
		if nrm.dot(centroid) < 0.0:
			pts.reverse()
			nrm = -nrm

		# 以主軸投影 UV，讓雜訊在世界座標上連續
		var ax := 0
		if absf(nrm.y) > absf(nrm.x) and absf(nrm.y) >= absf(nrm.z):
			ax = 1
		elif absf(nrm.z) > absf(nrm.x):
			ax = 2
		var ua := (ax + 1) % 3
		var ub := (ax + 2) % 3

		for k in range(1, pts.size() - 1):
			for p in [pts[0] as Vector3, pts[k] as Vector3, pts[k + 1] as Vector3]:
				var pos: Vector3 = p
				out_v.append(pos)
				out_n.append(nrm)
				var uv := Vector2.ZERO
				uv[0] = pos[ua]
				uv[1] = pos[ub]
				out_uv.append(uv)

	arrays[Mesh.ARRAY_VERTEX] = out_v
	arrays[Mesh.ARRAY_NORMAL] = out_n
	arrays[Mesh.ARRAY_TEX_UV] = out_uv

	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_mesh_cache[key] = mesh
	return mesh


## 圓角矩形平板（石碑的底座、月台等）
func slab(size: Vector3, chamfer := 0.04) -> ArrayMesh:
	return chamfer_box(size, chamfer)


## 由一條高度剖面生成環形山稜剪影
func mountain_ring(radius: float, height: float, segments: int, seed: int, jag := 0.35) -> ArrayMesh:
	# 法線改過。舊快取鍵不能沿用，否則這一局還是朝上的死黑楔形。
	var key := "mr2_%d_%d_%d" % [int(radius), int(height), seed]
	if _mesh_cache.has(key):
		return _mesh_cache[key]

	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var raw: Array = []
	for i in segments:
		var t := float(i) / float(segments) * TAU
		# 兩三組不同頻率的正弦疊出山稜，比純亂數有起伏但不平滑
		var h := height * (
			0.34
			+ 0.30 * sin(t * 2.0 + seed * 0.13)
			+ 0.20 * sin(t * 3.0 + 1.7)
			+ 0.14 * sin(t * 5.0 + 3.1)
			+ rng.randf_range(-jag, jag) * 0.16)
		raw.append(maxf(height * 0.10, h))

	# 三次平滑，去掉鋸齒
	var heights: Array = []
	for i in segments:
		var a: float = raw[(i - 1 + segments) % segments]
		var b: float = raw[i]
		var c: float = raw[(i + 1) % segments]
		var d: float = raw[(i + 2) % segments]
		heights.append((a + 3.0 * b + 3.0 * c + d) / 8.0)

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	var out_v := PackedVector3Array()
	var out_n := PackedVector3Array()

	for i in segments:
		var i2 := (i + 1) % segments
		var a0 := TAU * float(i) / float(segments)
		var a1 := TAU * float(i2) / float(segments)
		var p0 := Vector3(cos(a0) * radius, 0, sin(a0) * radius)
		var p1 := Vector3(cos(a1) * radius, 0, sin(a1) * radius)
		var q0 := p0 + Vector3(0, heights[i], 0)
		var q1 := p1 + Vector3(0, heights[i2], 0)
		# 鏡頭在環裡面。這個繞序的法線朝圓心，側面才吃得到側光。
		# 再加一點朝上，稜線才有天光，不會整圈都是剪影黑。
		var face := (q1 - p0).cross(q0 - p0)
		if face.length_squared() < 0.0001:
			face = Vector3.UP
		else:
			face = (face.normalized() + Vector3.UP * 0.28).normalized()
		out_v.append(p0); out_n.append(face)
		out_v.append(q1); out_n.append(face)
		out_v.append(q0); out_n.append(face)
		out_v.append(p0); out_n.append(face)
		out_v.append(q1); out_n.append(face)
		out_v.append(p1); out_n.append(face)

	arrays[Mesh.ARRAY_VERTEX] = out_v
	arrays[Mesh.ARRAY_NORMAL] = out_n
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_mesh_cache[key] = mesh
	return mesh


## 低多邊形球（角色關節、粒子、燈籠）
func blob(radius: float, rings := 6, segments := 10) -> SphereMesh:
	var key := "blob_%d_%d_%d" % [radius, rings, segments]
	if _mesh_cache.has(key):
		return _mesh_cache[key]
	var m := SphereMesh.new()
	m.radius = radius
	m.height = radius * 2.0
	m.radial_segments = segments
	m.rings = rings
	_mesh_cache[key] = m
	return m


# ── 材質 ────────────────────────────────────────────────────────────────
func road_material() -> ShaderMaterial:
	if _mat_cache.has("road"):
		return _mat_cache["road"]
	var m := ShaderMaterial.new()
	m.shader = _shader(SHADER_ROAD)
	_mat_cache["road"] = m
	return m


func stone_material(tint := Color(1, 1, 1)) -> ShaderMaterial:
	var key := "stone_%s" % tint.to_html(false)
	if _mat_cache.has(key):
		return _mat_cache[key]
	var m := ShaderMaterial.new()
	m.shader = _shader(SHADER_STONE)
	# 深玄武岩。亮度刻意壓低：碑面要靠「鑲嵌發光的假名」撐起視覺，
	# 石體本身越暗，假名越跳。
	m.set_shader_parameter("base_color", Color(0.021, 0.020, 0.032) * tint)
	m.set_shader_parameter("rim_color", Color(0.42, 0.58, 1.0))
	_mat_cache[key] = m
	return m


## 角色用：PBR + 輪廓光，夜晚剪影也能讀出形體
func toon_material(color: Color, rim := 0.55, rough := 0.62, emissive := 0.0) -> StandardMaterial3D:
	var key := "toon_%s_%.2f_%.2f_%.2f" % [color.to_html(false), rim, rough, emissive]
	if _mat_cache.has(key):
		return _mat_cache[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	m.metallic = 0.0
	m.rim_enabled = true
	m.rim = rim
	m.rim_tint = 0.7
	m.specular_mode = BaseMaterial3D.SPECULAR_SCHLICK_GGX
	if emissive > 0.0:
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = emissive
	_mat_cache[key] = m
	return m


func glow_material(color: Color, energy := 2.0) -> StandardMaterial3D:
	var key := "glow_%s_%.2f" % [color.to_html(false), energy]
	if _mat_cache.has(key):
		return _mat_cache[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(color.r, color.g, color.b, 0.0)
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.disable_receive_shadows = true
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = energy
	_mat_cache[key] = m
	return m


func flat_material(color: Color) -> StandardMaterial3D:
	var key := "flat_%s" % color.to_html(false)
	if _mat_cache.has(key):
		return _mat_cache[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.9
	m.metallic = 0.0
	_mat_cache[key] = m
	return m


# ── 環境 ────────────────────────────────────────────────────────────────
func build_environment(quality: int) -> Environment:
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = COL_SKY_TOP
	sky_mat.sky_horizon_color = COL_SKY_HORIZON
	sky_mat.sky_curve = 0.18
	sky_mat.ground_bottom_color = COL_SKY_GROUND
	sky_mat.ground_horizon_color = COL_SKY_HORIZON
	sky_mat.ground_curve = 0.08
	sky_mat.sun_angle_max = 12.0
	sky_mat.sun_curve = 0.08
	sky.sky_material = sky_mat
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_sky_contribution = 1.0
	env.ambient_light_energy = 0.80

	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_white = 3.2

	env.glow_enabled = true
	env.glow_intensity = 0.76
	env.glow_strength = 1.0
	env.glow_bloom = 0.07
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	env.glow_hdr_threshold = 1.05

	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	env.fog_light_color = Color(0.26, 0.22, 0.34)
	env.fog_light_energy = 0.70
	env.fog_density = 0.0048
	env.fog_sky_affect = 0.30

	# 調色留給 post_fx 一層。環境再拉飽和，燈籠光暈會被洗成同一種紫。
	env.adjustment_enabled = true
	env.adjustment_brightness = 1.02
	env.adjustment_contrast = 1.0
	env.adjustment_saturation = 1.0

	# 螢幕空間效果只在 Forward+ 且高畫質時開啟（行動端 / Web 直接跳過）
	if quality >= 2 and OS.has_feature("forward_plus"):
		env.ssao_enabled = true
		env.ssao_radius = 1.4
		env.ssao_intensity = 2.4
		env.ssao_power = 1.6
		env.ssao_detail = 0.6
		env.ssr_enabled = false
	return env


## 依單元主題切換場景色調
func apply_palette(env: Environment, sky: Sky, theme: int) -> void:
	var top: Color
	var horizon: Color
	var fill: Color
	var fog: Color
	match theme:
		1:  # 濁音：夕照朱
			top = Color(0.09, 0.035, 0.055)
			horizon = Color(0.62, 0.24, 0.20)
			fill = Color(1.0, 0.42, 0.30)
			fog = Color(0.34, 0.16, 0.18)
		2:  # 拗音：雪夜藍
			top = Color(0.045, 0.060, 0.115)
			horizon = Color(0.30, 0.42, 0.62)
			fill = Color(0.62, 0.80, 1.0)
			fog = Color(0.20, 0.26, 0.40)
		_:  # 清音：春夜櫻紫
			top = COL_SKY_TOP
			horizon = COL_SKY_HORIZON
			fill = COL_FILL
			fog = Color(0.20, 0.16, 0.32)
	var m := sky.sky_material as ProceduralSkyMaterial
	m.sky_top_color = top
	m.sky_horizon_color = horizon
	m.ground_horizon_color = horizon
	m.ground_bottom_color = top * 0.9
	env.fog_light_color = fog


func build_lights(theme := 0) -> Array:
	var key_light := DirectionalLight3D.new()
	key_light.light_color = Color(1.0, 0.90, 0.78)
	key_light.light_energy = 1.75
	key_light.shadow_enabled = true
	key_light.directional_shadow_max_distance = 80.0
	key_light.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	key_light.shadow_bias = 0.04
	key_light.shadow_normal_bias = 1.4
	key_light.rotation_degrees = Vector3(-42, 138, 0)

	var fill_light := DirectionalLight3D.new()
	fill_light.light_color = Color(0.92, 0.70, 0.84)
	fill_light.light_energy = 0.40
	fill_light.shadow_enabled = false
	fill_light.rotation_degrees = Vector3(-14, -40, 0)

	var rim_light := DirectionalLight3D.new()
	rim_light.light_color = Color(0.62, 0.74, 1.0)
	rim_light.light_energy = 0.55
	rim_light.shadow_enabled = false
	rim_light.rotation_degrees = Vector3(-8, 190, 0)

	return [key_light, fill_light, rim_light]


# ── 裝飾物 ──────────────────────────────────────────────────────────────
## 燈籠：夜色裡的主要光源之一，也是最好的速度線索
func make_lantern() -> Node3D:
	var root := Node3D.new()

	var post := MeshInstance3D.new()
	post.mesh = chamfer_box(Vector3(0.12, 2.1, 0.12), 0.03)
	post.material_override = flat_material(Color(0.10, 0.09, 0.14))
	post.position.y = 1.05
	root.add_child(post)

	var body := MeshInstance3D.new()
	body.mesh = blob(0.30, 8, 12)
	body.scale = Vector3(1.0, 1.25, 1.0)
	body.position.y = 2.30
	body.material_override = glow_material(COL_LANTERN, 4.6)
	root.add_child(body)

	var cap := MeshInstance3D.new()
	cap.mesh = chamfer_box(Vector3(0.44, 0.07, 0.44), 0.02)
	cap.position.y = 2.62
	cap.material_override = flat_material(Color(0.14, 0.10, 0.09))
	root.add_child(cap)

	var light := OmniLight3D.new()
	light.light_color = COL_LANTERN
	light.light_energy = 3.2
	light.omni_range = 7.0
	light.shadow_enabled = false
	light.position.y = 2.30
	root.add_child(light)

	return root


## 星野：MultiMesh 一次畫幾百顆，避免數百個 Node
func make_star_field(count: int, radius: float) -> MultiMeshInstance3D:
	var plane := PlaneMesh.new()
	plane.size = Vector2.ONE

	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.vertex_color_use_as_albedo = true
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.disable_receive_shadows = true

	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = plane
	plane.material = mat
	mm.instance_count = count

	var rng := RandomNumberGenerator.new()
	rng.seed = 20240917
	for i in count:
		var theta := rng.randf() * TAU
		var phi := acos(1.0 - rng.randf() * 0.6)     # 只佈置在地平線以上
		var dir := Vector3(sin(phi) * cos(theta), cos(phi), sin(phi) * sin(theta)).normalized()
		var s := rng.randf_range(0.45, 1.5)
		mm.set_instance_transform(i, Transform3D(Basis().scaled(Vector3(s, s, s)), dir * radius))
		var b := rng.randf_range(0.20, 0.68)
		mm.set_instance_color(i, Color(b, b * 0.96, b * 0.90, 1.0))

	var node := MultiMeshInstance3D.new()
	node.multimesh = mm
	return node


## 月亮：billboard 發光圓盤。位置刻意挑在遠山稜線之上，
## 否則會被山影吃掉，而且純球體在天空解析度下會像個白點。
func make_moon() -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(120, 120)
	mi.mesh = plane
	var m := ShaderMaterial.new()
	m.shader = _shader(SHADER_DISC)
	m.set_shader_parameter("color", Color(1.0, 0.97, 0.90))
	m.set_shader_parameter("energy", 1.5)
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.extra_cull_margin = 4000.0
	mi.position = Vector3(305, 158, -520)
	return mi


## 風切線：細長發光片，往鏡頭飛馳。速度感最直接的來源。
func make_speed_lines(count := 96) -> MultiMeshInstance3D:
	var plane := PlaneMesh.new()
	plane.size = Vector2(0.045, 6.0)

	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_color = Color(0.72, 0.84, 1.0, 0.0)
	mat.emission_enabled = true
	mat.emission = Color(0.72, 0.84, 1.0)
	mat.emission_energy_multiplier = 2.6
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.billboard_keep_scale = true
	mat.disable_receive_shadows = true

	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = plane
	plane.material = mat
	mm.instance_count = count

	var node := MultiMeshInstance3D.new()
	node.multimesh = mm
	return node


# ── 3D 文字 ─────────────────────────────────────────────────────────────
static var _shadow_tex: ImageTexture


## 程序化的柔和圓形貼圖：當作接地陰影 / 光暈 / 粒子底圖
static func radial_texture(size := 64, power := 2.2) -> ImageTexture:
	var key := "radial_%d_%.2f" % [size, power]
	if _radial_cache.has(key):
		return _radial_cache[key]
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var c := float(size) * 0.5
	for y in size:
		for x in size:
			var d := Vector2(float(x) - c + 0.5, float(y) - c + 0.5).length() / c
			var a := pow(clampf(1.0 - d, 0.0, 1.0), power)
			img.set_pixel(x, y, Color(1, 1, 1, a))
	var t := ImageTexture.create_from_image(img)
	_radial_cache[key] = t
	return t


## 角色腳下的接地陰影
func make_contact_shadow(radius := 0.62) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2.ONE * radius * 2.0
	mi.mesh = plane
	var m := ShaderMaterial.new()
	m.shader = _shader(SHADER_BLOB)
	m.set_shader_parameter("strength", 0.62)
	m.set_shader_parameter("power", 2.2)
	mi.material_override = m
	mi.position.y = 0.03
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


## 碑面上的假名。描邊 + 自發光，才能在高速下仍然清楚。
func make_kana_label() -> Label3D:
	var l := Label3D.new()
	l.font = FontKit.display
	l.font_size = 128
	l.pixel_size = 0.004
	l.outline_size = 5
	l.outline_render_priority = 1
	l.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	l.shaded = false
	l.double_sided = false
	l.alpha_cut = Label3D.ALPHA_CUT_DISCARD
	l.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.outline_modulate = Color(0.10, 0.055, 0.01, 1.0)
	l.modulate = COL_INLAY
	return l


## 羅馬字選項用 UI 字型（拉丁字形較細）
func make_romaji_label() -> Label3D:
	var l := Label3D.new()
	l.font = FontKit.bold
	l.font_size = 96
	l.pixel_size = 0.0135
	l.outline_size = 6
	l.outline_render_priority = 1
	l.shaded = false
	l.double_sided = false
	l.alpha_cut = Label3D.ALPHA_CUT_DISCARD
	l.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.outline_modulate = Color(0.06, 0.04, 0.01, 1.0)
	l.modulate = Color(0.80, 0.94, 1.0)
	return l
