shader_type canvas_item;
render_mode unshaded;

// 全螢幕後製：徑向模糊、色散、暗角、顆粒、受擊染色、閃白。
// 模糊取螢幕紋理的粗略 mip，因此需要 filter_linear_mipmap。

uniform sampler2D screen_tex : hint_screen_texture, repeat_disable, filter_linear_mipmap;

uniform float speed_blur : hint_range(0.0, 1.0) = 0.0;
uniform float aberration : hint_range(0.0, 6.0) = 1.0;
uniform float vignette : hint_range(0.0, 2.0) = 0.85;
uniform float grain : hint_range(0.0, 0.4) = 0.045;
uniform float saturation : hint_range(0.0, 2.0) = 1.10;
uniform float contrast : hint_range(0.0, 2.0) = 1.06;
uniform float lift : hint_range(-0.2, 0.2) = 0.0;
uniform float flash : hint_range(0.0, 1.0) = 0.0;
uniform vec4 flash_color : source_color = vec4(1.0);
uniform float damage : hint_range(0.0, 1.0) = 0.0;
uniform float focus_pulse : hint_range(0.0, 1.0) = 0.0;
uniform vec3 tint : source_color = vec3(1.0);
uniform float reduce_motion : hint_range(0.0, 1.0) = 0.0;

float hash21(vec2 p) {
	p = fract(p * vec2(127.31, 311.7));
	p += dot(p, p + 34.23);
	return fract(p.x * p.y);
}

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 center = vec2(0.5);
	vec2 to_c = uv - center;
	float r = length(to_c);
	float r2 = r * r;

	// 動態模糊强度隨半徑平方增長，中心保持銳利
	float blur = speed_blur * (1.0 - reduce_motion * 0.85);
	float lod = blur * 5.5 * r2;

	vec3 col;
	col.r = textureLod(screen_tex, uv, lod).r;
	col.g = textureLod(screen_tex, uv, lod).g;
	col.b = textureLod(screen_tex, uv, lod).b;

	// 色散：只在畫面外圈分離
	float ab = aberration * (1.0 - reduce_motion * 0.9) * 0.0022 * r2;
	if (ab > 0.00001) {
		col.r = textureLod(screen_tex, uv + to_c * ab, lod).r;
		col.b = textureLod(screen_tex, uv - to_c * ab, lod).b;
	}

	// 色調分級：對比 + 飽和 + lift
	col = (col - 0.5) * contrast + 0.5 + lift;
	float lum = dot(col, vec3(0.2126, 0.7152, 0.0722));
	col = mix(vec3(lum), col, saturation);
	col *= tint;

	// 焦點脈動：答對時短暫拉近
	if (focus_pulse > 0.0) {
		float zoom = focus_pulse * 0.006 * (1.0 - reduce_motion);
		vec2 zuv = center + to_c * (1.0 - zoom);
		vec3 z = textureLod(screen_tex, zuv, 0.0).rgb;
		z = (z - 0.5) * contrast + 0.5 + lift;
		float zl = dot(z, vec3(0.2126, 0.7152, 0.0722));
		z = mix(vec3(zl), z, saturation) * tint;
		col = mix(col, z, focus_pulse * 0.35);
	}

	// 受擊：邊緣染紅 + 脈動
	if (damage > 0.0) {
		float edge = smoothstep(0.18, 0.72, r);
		col = mix(col, vec3(0.85, 0.10, 0.16), edge * damage * 0.72);
		col *= 1.0 - damage * 0.10;
	}

	// 答對閃光
	col = mix(col, flash_color.rgb, flash * flash_color.a);

	// 暗角
	col *= 1.0 - vignette * r2 * 0.95;

	// 顆粒
	float g = hash21(uv * vec2(1920.0, 1080.0) + fract(TIME) * 91.7) - 0.5;
	col += g * grain;

	COLOR = vec4(max(col, vec3(0.0)), 1.0);
}
