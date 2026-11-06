shader_type canvas_item;

uniform sampler2D metal_mask : filter_nearest, repeat_disable;
uniform vec2 source_top_center = vec2(127.5, 94.0);
uniform vec2 top_half_size = vec2(75.5, 66.0);
varying vec2 source_pixel;

void vertex() {
	source_pixel = VERTEX;
}

void fragment() {
	// Камень ограничен плоскостью тайла; выдвинутые кончики могут выступать над её краем.
	// Маска повторяет только выбранные пиксели металла соответствующей позы PixelLab.
	vec2 diamond = abs(source_pixel - source_top_center) / top_half_size;
	float surface = step(diamond.x + diamond.y, 1.0);
	COLOR.a *= max(surface, step(0.5, texture(metal_mask, UV).r));
}
