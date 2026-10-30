// Только выбранный Щитоносец включает этот профиль; остальные материалы сохраняют RGB.
uniform float shieldbearer_palette_strength : hint_range(0.0, 1.0) = 0.0;

vec3 shieldbearer_material_palette(vec3 rgb) {
	if (shieldbearer_palette_strength <= 0.0) {
		return rgb;
	}
	float luminance = dot(rgb, vec3(0.2126, 0.7152, 0.0722));
	float chroma = max(rgb.r, max(rgb.g, rgb.b)) - min(rgb.r, min(rgb.g, rgb.b));
	// Холодные/нейтральные серые относятся к стали и седине; кожа и ткань сохраняют цветовую семью.
	float metal = (1.0 - smoothstep(0.12, 0.30, chroma))
		* (1.0 - smoothstep(0.04, 0.16, rgb.r - rgb.b));
	// Небольшие световые переходы собираем в крупные тональные ступени без изменения alpha/UV.
	vec3 steel = vec3(0.055, 0.045, 0.065);
	steel = mix(steel, vec3(0.20, 0.17, 0.19), smoothstep(0.10, 0.16, luminance));
	steel = mix(steel, vec3(0.53, 0.51, 0.49), smoothstep(0.28, 0.40, luminance));
	steel = mix(steel, vec3(0.78, 0.76, 0.72), smoothstep(0.52, 0.65, luminance));
	steel = mix(steel, vec3(0.93, 0.90, 0.83), smoothstep(0.79, 0.90, luminance));
	// Более глубокие тени и насыщенные полутона отделяют кожу, дерево и красную ткань от камня.
	float contrast = clamp((luminance - 0.32) * 1.15 + 0.32, 0.0, 1.0);
	vec3 colored = mix(vec3(luminance), rgb, 1.18) * contrast / max(luminance, 0.001);
	vec3 graded = mix(clamp(colored, vec3(0.0), vec3(1.0)), steel, metal);
	return mix(rgb, graded, shieldbearer_palette_strength);
}
