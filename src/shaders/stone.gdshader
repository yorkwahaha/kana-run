shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

// 石碑材質：深玄武岩。細部靠雜訊與垂直風化痕跡，
// 邊緣以菲涅耳挑出輪廓光，讓黑色石體在夜色中仍然立體。

uniform vec3 base_color : source_color = vec3(0.021, 0.020, 0.032);
uniform vec3 mineral_color : source_color = vec3(0.105, 0.112, 0.155);
uniform vec3 rim_color : source_color = vec3(0.42, 0.58, 1.0);
uniform float uv_scale : hint_range(0.1, 8.0) = 0.9;
uniform float grain_scale : hint_range(1.0, 40.0) = 11.0;
uniform float rim_power : hint_range(0.5, 8.0) = 3.2;
uniform float rim_gain : hint_range(0.0, 4.0) = 0.55;
uniform float vein_gain : hint_range(0.0, 3.0) = 0.22;
uniform float crack_gain : hint_range(0.0, 2.0) = 0.30;
uniform float highlight : hint_range(0.0, 4.0) = 0.0;   // 答對時整體發光

float hash21(vec2 p) {
	p = fract(p * vec2(127.31, 311.7));
	p += dot(p, p + 34.23);
	return fract(p.x * p.y);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash21(i), hash21(i + vec2(1.0, 0.0)), f.x),
			   mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0, 1.0)), f.x), f.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += a * vnoise(p);
		p *= 2.11;
		a *= 0.5;
	}
	return v;
}

void fragment() {
	vec2 uv = UV * uv_scale;
	float n = fbm(uv * grain_scale);
	float speck = vnoise(uv * grain_scale * 7.0);

	// 垂直風化條痕
	float streak = fbm(vec2(uv.x * grain_scale * 1.6, uv.y * grain_scale * 0.22));

	vec3 albedo = mix(base_color, mineral_color, n * 0.85 + speck * 0.10);
	albedo = mix(albedo, albedo * 0.72, streak * 0.5);
	ALBEDO = albedo;

	// 礦脈：脊線噪聲
	float vein = 1.0 - abs(fbm(uv * 4.7) * 2.0 - 1.0);
	vein = pow(clamp(vein, 0.0, 1.0), 6.0);

	// 裂紋：稀薄的高頻脊線
	float crack = 1.0 - abs(fbm(uv * 9.3 + 17.0) * 2.0 - 1.0);
	crack = pow(clamp(crack, 0.0, 1.0), 14.0);

	ROUGHNESS = clamp(0.82 - n * 0.22 - vein * 0.3, 0.16, 1.0);
	METALLIC = vein * 0.30;

	// 注意：Godot 的 VIEW 是「片段在視空間的位置」，方向是離開鏡頭的，
	// 所以指向鏡頭的向量是 -VIEW。寫成 dot(NORMAL, VIEW) 會恆為負，
	// 導致整面石牆都被菲涅耳邊光灌滿（看起來像藍色玉）。
	vec3 to_cam = normalize(-VIEW);
	float fres = pow(1.0 - clamp(dot(normalize(NORMAL), to_cam), 0.0, 1.0), rim_power);
	vec3 emis = rim_color * fres * rim_gain;
	emis += mineral_color * vein * vein_gain;
	emis += vec3(0.02) * crack * crack_gain;
	emis += vec3(1.0, 0.86, 0.55) * highlight * (0.25 + fres * 0.7);
	EMISSION = emis;
}
