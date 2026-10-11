shader_type canvas_item;

// Сетка задана в игровом размере: зум не выбирает новые детали большого исходника.
uniform vec4 source_region = vec4(0.0, 0.0, 312.0, 292.0);
uniform vec2 native_size = vec2(78.0, 73.0);
varying vec4 sprite_modulate;

void vertex() {
	sprite_modulate = COLOR;
}

void fragment() {
	vec2 source_pixel = UV / TEXTURE_PIXEL_SIZE;
	vec2 local_uv = (source_pixel - source_region.xy) / source_region.zw;
	vec2 position = local_uv * native_size;
	vec2 cell = floor(position);
	// Покрытие экранного пикселя удерживает тонкие линии между дробными шагами.
	// При 1:1 и целой позиции остаётся ровно один texel, без общего размытия.
	vec2 footprint = clamp(fwidth(position), vec2(0.0001), vec2(2.0));
	vec2 low = position - footprint * 0.5;
	vec2 high = position + footprint * 0.5;
	vec4 sum = vec4(0.0);
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 neighbor = cell + vec2(float(x), float(y));
			vec2 overlap = max(vec2(0.0), min(high, neighbor + vec2(1.0)) - max(low, neighbor));
			float weight = overlap.x * overlap.y / (footprint.x * footprint.y);
			// Builtin TEXTURE читаем здесь: передача sampler в helper ломала headless codegen.
			vec4 color = vec4(0.0);
			if (all(greaterThanEqual(neighbor, vec2(0.0))) && all(lessThan(neighbor, native_size))) {
				vec2 pixel = source_region.xy + (neighbor + vec2(0.5)) * source_region.zw / native_size;
				color = texture(TEXTURE, pixel * TEXTURE_PIXEL_SIZE);
				// Покрытие границы считаем отдельно от ореола большого исходника.
				color.a = step(0.5, color.a);
				color = vec4(color.rgb * color.a, color.a);
			}
			sum += color * weight;
		}
	}
	vec3 rgb = sum.a > 0.0 ? sum.rgb / sum.a : vec3(0.0);
	COLOR = vec4(rgb, sum.a) * sprite_modulate;
}
