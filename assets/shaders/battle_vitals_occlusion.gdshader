shader_type canvas_item;

uniform int blocker_count = 0;
uniform vec4 blocker_rects[64];

void fragment() {
	vec2 fragment_position = FRAGCOORD.xy;
	for (int index = 0; index < blocker_count; index++) {
		vec4 bounds = blocker_rects[index];
		if (fragment_position.x >= bounds.x && fragment_position.y >= bounds.y
				&& fragment_position.x < bounds.z && fragment_position.y < bounds.w) {
			discard;
		}
	}
	// COLOR уже включает текстуру: повторное умножение испортило бы сглаженные цифры.
}
