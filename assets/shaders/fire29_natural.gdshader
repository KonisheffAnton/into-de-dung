shader_type canvas_item;

uniform sampler2D fixed_mask : filter_linear;

void fragment() {
	// Сохраняем входной modulate: он управляет fade опасности при её исчезновении.
	COLOR.a *= texture(fixed_mask, UV).r;
}
