shader_type canvas_item;

uniform vec2 source_top_center = vec2(128.0, 100.0);
uniform vec2 top_half_size = vec2(64.0, 48.0);
varying vec2 source_pixel;

void vertex() {
	source_pixel = VERTEX;
}

void fragment() {
	// Координаты кадра не зависят от региона атласа: каменные боковины остаются за ромбом.
	vec2 diamond = abs(source_pixel - source_top_center) / top_half_size;
	COLOR.a *= step(diamond.x + diamond.y, 1.0);
}
