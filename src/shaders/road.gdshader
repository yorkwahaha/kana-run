shader_type spatial;
render_mode depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

// 程序化柏油路面：無貼圖，靠雜訊 + 積水 + 車道線 + 邊緣流光。
//
// 捲動跟世界走的距離綁在一起，不跟 TIME。
// 暫停、倒地、三選一時 advance() 停了，貼圖也就停了。
// 以前用 TIME * scroll_speed，速度歸零還在滾，而且跟幾何虛線對不齊。

uniform vec3 base_color : source_color = vec3(0.195, 0.184, 0.250);
uniform vec3 wet_color : source_color = vec3(0.16, 0.28, 0.46);
uniform vec3 rail_color : source_color = vec3(0.42, 0.52, 1.0);
uniform float uv_repeat : hint_range(1.0, 64.0) = 26.0;
uniform float scroll_speed : hint_range(0.0, 40.0) = 6.0;
uniform float travel : hint_range(0.0, 1000.0) = 0.0;
uniform float road_length : hint_range(1.0, 1000.0) = 240.0;
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
	float span = max(road_length, 1.0);
	float shift = travel / span;
	vec2 p = vec2(uv.x * 6.0, uv.y * uv_repeat - shift * uv_repeat);

	// 兩層不同尺度的砂石顆粒。對比拉高，近處才看得出是路而不是一塊色。
	float coarse = fbm(p * 1.7);
	float fine = vnoise(p * 24.0);
	float asphalt = clamp(mix(coarse, fine, 0.45) * grain, 0.0, 1.0);

	// 積水：低頻噪聲做出斑塊，降低粗糙度
	float puddle = smoothstep(0.52, 0.78, fbm(vec2(uv.x * 2.4, uv.y * 3.1 - shift * 2.0)));
	puddle *= wetness;

	vec3 albedo = mix(base_color * 0.72, base_color * 2.15, asphalt);
	albedo = mix(albedo, wet_color, puddle * 0.75);

	// 濕路面如果亮到接近鏡面，光暈會把車道中間炸成一塊白。
	float rough = mix(0.88 - asphalt * 0.10, 0.32, puddle);
	ROUGHNESS = clamp(rough, 0.18, 1.0);
	METALLIC = puddle * 0.04;

	// 三條跑道的分界在 ±1.35 公尺（車道中心 ±2.7，路寬 10）。
	// 連續線把幾何虛線串起來；虛線本身仍是場景裡的亮塊。
	float div_w = 0.012;
	float lane = 1.0 - smoothstep(0.0, div_w, abs(uv.x - 0.365));
	lane = max(lane, 1.0 - smoothstep(0.0, div_w, abs(uv.x - 0.635)));
	albedo = mix(albedo, albedo + rail_color * 0.55, lane);
	ALBEDO = albedo;

	// 邊緣流光：左右兩條導軌 + 沿長度流動的光帶
	float ex = min(uv.x, 1.0 - uv.x);
	float rail = 1.0 - smoothstep(0.0, rail_width, ex);
	float pulse = vnoise(vec2(uv.x * 2.0, uv.y * streak_density - shift * streak_density * 1.6));
	pulse = pow(clamp(pulse, 0.0, 1.0), 3.0);
	float fade = smoothstep(0.0, 0.35, uv.y);
	EMISSION = rail_color * (rail * (0.35 + pulse * rail_gain) + lane * 0.45) * fade;
}
