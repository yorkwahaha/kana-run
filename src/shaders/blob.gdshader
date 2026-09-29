shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, unshaded, shadows_disabled;

// 程序化的柔和圓形遮罩。相較貼圖，著色器版本不會因為
// 貼圖過濾／mip 設定而在某些角度變成硬邊方塊。

uniform vec3 color : source_color = vec3(0.0, 0.0, 0.0);
uniform float strength : hint_range(0.0, 1.0) = 0.55;
uniform float power : hint_range(0.5, 8.0) = 2.4;

void fragment() {
	float d = length(UV - vec2(0.5)) * 2.0;
	float a = pow(clamp(1.0 - d, 0.0, 1.0), power) * strength;
	ALBEDO = color;
	ALPHA = a;
}
