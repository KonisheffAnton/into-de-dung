shader_type canvas_item;

uniform float flame_gain = 1.12;

void fragment() {
	// Alpha содержит только исходные языки PixelLab; ромб пола не должен обрезать их кончики.
	COLOR.rgb = min(COLOR.rgb * flame_gain, vec3(1.0));
}
