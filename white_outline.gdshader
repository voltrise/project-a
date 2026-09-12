shader_type canvas_item;

uniform vec4 outline_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float outline_width : hint_range(0.0, 5.0) = 1.0;
uniform bool enabled = false;

void fragment() {
	vec4 col = texture(TEXTURE, UV);
	if (enabled) {
		vec2 size = TEXTURE_PIXEL_SIZE * outline_width;
		float a_top = texture(TEXTURE, UV + vec2(0.0, -size.y)).a;
		float a_bot = texture(TEXTURE, UV + vec2(0.0, size.y)).a;
		float a_left = texture(TEXTURE, UV + vec2(-size.x, 0.0)).a;
		float a_right = texture(TEXTURE, UV + vec2(size.x, 0.0)).a;
		float a_tl = texture(TEXTURE, UV + vec2(-size.x, -size.y)).a;
		float a_tr = texture(TEXTURE, UV + vec2(size.x, -size.y)).a;
		float a_bl = texture(TEXTURE, UV + vec2(-size.x, size.y)).a;
		float a_br = texture(TEXTURE, UV + vec2(size.x, size.y)).a;

		float a_max = max(max(max(a_top, a_bot), max(a_left, a_right)), max(max(a_tl, a_tr), max(a_bl, a_br)));

		if (col.a < 0.1 && a_max > 0.1) {
			COLOR = outline_color;
		} else {
			COLOR = col;
		}
	} else {
		COLOR = col;
	}
}
