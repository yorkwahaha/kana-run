shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix, depth_draw_opaque;

// 立繪維持不打光。場景光打在剪影上會髒。
// 只在透明邊緣加一圈冷色，讓人從柏油和夜色裡分離出來。

uniform sampler2D tex : source_color, filter_linear_mipmap, repeat_disable;
uniform vec3 rim_color : source_color = vec3(0.72, 0.82, 1.0);
uniform float rim_gain : hint_range(0.0, 1.5) = 0.42;

void fragment() {
	vec4 body = texture(tex, UV);
	float ax = texture(tex, UV + vec2(0.010, 0.0)).a;
	float ay = texture(tex, UV + vec2(0.0, 0.008)).a;
	float bx = texture(tex, UV - vec2(0.010, 0.0)).a;
	float by = texture(tex, UV - vec2(0.0, 0.008)).a;
	float edge = clamp(body.a - min(min(ax, bx), min(ay, by)), 0.0, 1.0);
	vec3 rim = rim_color * edge * rim_gain;
	ALBEDO = body.rgb + rim;
	EMISSION = rim * 0.85;
	ALPHA = body.a;
}
