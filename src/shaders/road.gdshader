shader_type spatial;
render_mode depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

// 程序化柏油路面：無貼圖，靠雜訊 + 積水 + 邊緣流光。
// UV.y 沿著跑道長度，隨 TIME 捲動形成無限延伸的錯覺。
//
// 捲動方向很容易搞反：PlaneMesh 的 v=0 在「遠端」（-z），v=1 在「近端」
// （鏡頭後方）。而 f(p + c*t) 會讓特徵往 p 減小的方向移動，
// 所以正的 scroll 會讓路面紋理往**遠處**流 —— 與幾何虛線往近處移動
// 正好相反，看起來就像在追著馬路跑。取負號才對齊。

uniform vec3 base_color : source_color = vec3(0.195, 0.184, 0.250);
uniform vec3 wet_color : source_color = vec3(0.16, 0.28, 0.46);
uniform vec3 rail_color : source_color = vec3(0.42, 0.52, 1.0);
uniform float uv_repeat : hint_range(1.0, 64.0) = 26.0;
uniform float scroll_speed : hint_range(0.0, 40.0) = 6.0;
uniform float wetness : hint_range(0.0, 1.0) = 0.42;
uniform float grain : hint_range(0.0, 3.0) = 1.0;
uniform float rail_width : hint_range(0.01, 0.5) = 0.075;
uniform float rail_gain : hint_range(0.0, 8.0) = 1.05;
uniform float streak_density : hint_range(0.0, 60.0) = 14.0;

float hash21(vec2 p) {
	p = fract(p * vec2(127.31, 311.7));
	p += dot(p, p + 34.23);
	return fract(p.x * p.y);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += a * vnoise(p);
		p *= 2.03;
		a *= 0.5;
	}
	return v;
}

void fragment() {
	vec2 uv = UV;
	float scroll = -TIME * scroll_speed * 0.01;
	vec2 p = vec2(uv.x * 6.0, uv.y * uv_repeat + scroll * uv_repeat);

	// 兩層不同尺度的砂石顆粒
	float coarse = fbm(p * 1.7);
	float fine = vnoise(p * 24.0);
	float asphalt = mix(coarse, fine, 0.45) * grain;

	// 積水：低頻噪聲做出斑塊，降低粗糙度
	float puddle = smoothstep(0.52, 0.78, fbm(vec2(uv.x * 2.4, uv.y * 3.1 + scroll * 2.0)));
	puddle *= wetness;

	vec3 albedo = mix(base_color, base_color * 1.9, asphalt);
	albedo = mix(albedo, wet_color, puddle * 0.75);
	ALBEDO = albedo;

	float rough = mix(0.86 - asphalt * 0.12, 0.09, puddle);
	ROUGHNESS = clamp(rough, 0.05, 1.0);
	METALLIC = puddle * 0.15;

	// 邊緣流光：左右兩條導軌 + 沿長度流動的光帶
	float ex = min(uv.x, 1.0 - uv.x);
	float rail = 1.0 - smoothstep(0.0, rail_width, ex);
	float pulse = vnoise(vec2(uv.x * 2.0, uv.y * streak_density - scroll * streak_density * 3.0));
	pulse = pow(clamp(pulse, 0.0, 1.0), 3.0);
	float fade = smoothstep(0.0, 0.35, uv.y);
	EMISSION = rail_color * rail * (0.35 + pulse * rail_gain) * fade;
}
