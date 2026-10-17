shader_type canvas_item;

#include "character_palette.gdshaderinc"

varying vec4 sprite_modulate;

void vertex() {
	sprite_modulate = COLOR;
}

void fragment() {
	// Fallback-фигуры сохраняют прежнюю выборку текстуры, alpha и цвет своей фракции.
	vec4 source = texture(TEXTURE, UV);
	COLOR = vec4(brighter_character_palette(source.rgb), source.a) * sprite_modulate;
}
