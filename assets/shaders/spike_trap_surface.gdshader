shader_type canvas_item;

uniform sampler2D metal_mask : filter_nearest, repeat_disable;
varying vec2 source_pixel;

void vertex() {
	source_pixel = VERTEX;
}

void fragment() {
	// Камень ограничен плоскостью тайла; выдвинутые кончики могут выступать над её краем.
	// Маска повторяет только выбранные пиксели металла соответствующей позы PixelLab.
	vec2 diamond = abs(source_pixel - vec2(128.0, 100.0)) / vec2(64.0, 48.0);
	float surface = step(diamond.x + diamond.y, 1.0);
	COLOR.a *= max(surface, step(0.5, texture(metal_mask, UV).r));
}
