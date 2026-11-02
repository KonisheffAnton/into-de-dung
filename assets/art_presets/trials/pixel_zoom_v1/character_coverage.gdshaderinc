// Разрешение игровой сетки хранится лишь для старой раскладки масок ткани.
uniform vec4 source_region = vec4(0.0);
uniform vec2 native_size = vec2(128.0);
uniform bool cloth_enabled = false;
uniform sampler2D cloth_masks : filter_nearest, repeat_disable;
uniform vec2 cloth_mask_origin = vec2(0.0);
uniform vec4 cloth_shadow : source_color = vec4(0.35, 0.35, 0.18, 1.0);
uniform vec4 cloth_light : source_color = vec4(0.52, 0.51, 0.25, 1.0);
// Нативные модели сохраняют старый alpha cutoff; fallback-спрайты сохраняют исходную прозрачность.
uniform bool source_alpha_cutout = true;
varying vec4 sprite_modulate;

void vertex() {
	sprite_modulate = COLOR;
}

void fragment() {
	vec2 texture_size = vec2(1.0) / TEXTURE_PIXEL_SIZE;
	vec4 region = source_region;
	if (region.z <= 0.0 || region.w <= 0.0) {
		region = vec4(vec2(0.0), texture_size);
	}
	// Координаты и покрытие считаются в исходных текселях, поэтому масштаб не теряет пиксели по сетке.
	vec2 position = UV / TEXTURE_PIXEL_SIZE - region.xy;
	vec2 footprint = max(fwidth(position), vec2(0.0001));
	vec2 low = max(position - footprint * 0.5, vec2(0.0));
	vec2 high = min(position + footprint * 0.5, region.zw);
	vec4 sum = vec4(0.0);
	int first_x = int(floor(low.x));
	int first_y = int(floor(low.y));
	int end_x = int(ceil(high.x));
	int end_y = int(ceil(high.y));
	for (int y = first_y; y < end_y; y++) {
		for (int x = first_x; x < end_x; x++) {
			vec2 texel = vec2(float(x), float(y));
			vec2 overlap = max(vec2(0.0), min(high, texel + vec2(1.0)) - max(low, texel));
			float weight = overlap.x * overlap.y / (footprint.x * footprint.y);
			vec2 sample_pixel = region.xy + texel + vec2(0.5);
			// Встроенный sampler читается прямо во fragment: helper с sampler ломал headless codegen.
			vec4 color = texture(TEXTURE, sample_pixel * TEXTURE_PIXEL_SIZE);
			if (cloth_enabled) {
				// Маски используют прежнюю игровую сетку, хотя фильтрация цвета больше не зависит от неё.
				vec2 mask_cell = floor((texel + vec2(0.5)) * native_size / region.zw);
				if (texture(cloth_masks, (cloth_mask_origin + mask_cell + vec2(0.5)) / vec2(1280.0)).r > 0.5) {
					float luminance = dot(color.rgb, vec3(0.2126, 0.7152, 0.0722));
					float shade = clamp((luminance - 0.34) / 0.15, 0.0, 1.0);
					vec3 ramp = mix(cloth_shadow.rgb, cloth_light.rgb, shade);
					color.rgb = ramp * min(1.0, luminance / 0.34);
				}
			}
			color.rgb = brighter_character_palette(color.rgb);
			color.rgb = shieldbearer_material_palette(color.rgb);
			color.a = source_alpha_cutout ? step(0.5, color.a) : color.a;
			color.rgb *= color.a;
			sum += color * weight;
		}
	}
	vec3 rgb = sum.a > 0.0 ? sum.rgb / sum.a : vec3(0.0);
	COLOR = vec4(rgb, sum.a) * sprite_modulate;
}
