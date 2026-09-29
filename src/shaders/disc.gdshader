shader_type spatial;
render_mode blend_add, depth_draw_never, cull_disabled, unshaded, shadows_disabled;

// 柔和的發光圓盤（月亮／遠處的燈球）。用 billboard 平面而非球體，
// 因為在天空的解析度下，平面 + 柔邊反而比較像真正的發光源。

uniform vec3 color : source_color = vec3(1.0, 0.97, 0.90);
uniform float core_power : hint_range(0.5, 8.0) = 2.2;
uniform float halo_power : hint_range(0.5, 8.0) = 1.1;
uniform float halo_gain : hint_range(0.0, 4.0) = 0.55;
uniform float energy : hint_range(0.0, 8.0) = 1.4;

void fragment() {
	float d = length(UV - vec2(0.5)) * 2.0;
	float core = pow(clamp(1.0 - d, 0.0, 1.0), core_power);
	float halo = pow(clamp(1.0 - d, 0.0, 1.0), halo_power) * halo_gain;
	ALBEDO = color * (core + halo) * energy;
	ALPHA = 1.0;
}
