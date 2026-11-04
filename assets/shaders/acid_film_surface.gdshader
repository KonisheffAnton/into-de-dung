shader_type canvas_item;
render_mode unshaded;

uniform vec2 source_top_center = vec2(128.0, 100.0);
uniform vec2 top_half_size = vec2(64.0, 48.0);
uniform float film_opacity : hint_range(0.0, 1.0) = 0.58;
varying vec2 source_pixel;

void vertex() {
	source_pixel = VERTEX;
}

void fragment() {
	vec2 diamond = abs(source_pixel - source_top_center) / top_half_size;
	// Камень исходника нейтрален; зелёная плёнка смешивается с реальным полом.
	float green = COLOR.g - max(COLOR.r, COLOR.b);
	COLOR.a *= step(diamond.x + diamond.y, 1.0) * smoothstep(0.015, 0.14, green) * film_opacity;
}
