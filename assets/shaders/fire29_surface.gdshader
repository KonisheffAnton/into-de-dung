shader_type canvas_item;

// Плоскость огня берётся внутри торца исходного блока и заполняет весь игровой тайл.
uniform vec2 source_top_center = vec2(128.0, 99.4580897);
uniform vec2 top_half_size = vec2(115.162242, 87.3567251);
varying vec2 source_pixel;

void vertex() {
	source_pixel = VERTEX;
}

void fragment() {
	vec2 diamond = abs(source_pixel - source_top_center) / top_half_size;
	COLOR.a *= step(diamond.x + diamond.y, 1.0);
}
