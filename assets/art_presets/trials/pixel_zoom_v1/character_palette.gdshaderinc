uniform float brighter_palette_strength : hint_range(0.0, 1.0) = 0.0;

vec3 brighter_character_palette(vec3 rgb) {
	// Цветовая проба стражника: светлее полутона, насыщеннее материалы, глубокие тени прежние.
	float luminance = dot(rgb, vec3(0.2126, 0.7152, 0.0722));
	float midtone = smoothstep(0.08, 0.30, luminance);
	vec3 saturated = mix(vec3(luminance), rgb, 1.10);
	vec3 brighter = saturated + 0.18 * saturated * (vec3(1.0) - saturated);
	return mix(rgb, clamp(brighter, vec3(0.0), vec3(1.0)), brighter_palette_strength * midtone);
}
