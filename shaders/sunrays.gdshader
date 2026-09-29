shader_type canvas_item;
render_mode blend_add;

uniform vec2 light_pos = vec2(0.72, 0.05);
uniform int samples : hint_range(16, 64) = 36;
uniform float density : hint_range(0.0, 1.0) = 0.85;
uniform float weight : hint_range(0.0, 0.5) = 0.06;
uniform float decay : hint_range(0.5, 1.0) = 0.96;
uniform float exposure : hint_range(0.0, 3.0) = 0.9;
uniform vec4 ray_color : source_color = vec4(0.85, 0.95, 1.0, 0.8);
uniform float threshold : hint_range(0.0, 1.0) = 0.50;
uniform float noise_speed : hint_range(0.0, 2.0) = 0.15;
uniform float ray_spread : hint_range(0.5, 2.0) = 1.0;

uniform sampler2D screen_texture : hint_screen_texture, filter_linear;

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 delta_uv = (uv - light_pos) * (1.0 / float(samples)) * density * ray_spread;
	
	vec3 col = vec3(0.0);
	float illumination_decay = 1.0;
	vec2 cur_uv = uv;
	float time_offset = TIME * noise_speed;
	
	for (int i = 0; i < samples; i++) {
		cur_uv -= delta_uv;
		if (cur_uv.x < 0.0 || cur_uv.x > 1.0 || cur_uv.y < 0.0 || cur_uv.y > 1.0) {
			illumination_decay *= decay;
			continue;
		}
		
		vec4 sample_col = texture(screen_texture, cur_uv);
		float lum = dot(sample_col.rgb, vec3(0.299, 0.587, 0.114));
		if (lum > threshold) {
			float strength = (lum - threshold) / (1.0 - threshold);
			float ray_noise = 0.92 + 0.16 * sin(cur_uv.x * 35.0 + cur_uv.y * 25.0 + time_offset);
			col += sample_col.rgb * strength * illumination_decay * weight * ray_noise;
		}
		illumination_decay *= decay;
	}
	
	// Soft tone mapping: prevents nuclear white blowout, produces smooth ethereal beams
	col = vec3(1.0) - exp(-col * exposure);
	col *= ray_color.rgb;
	
	// Smooth fade toward bottom
	float bottom_fade = smoothstep(1.0, 0.70, uv.y);
	col *= bottom_fade;
	
	COLOR = vec4(col, 1.0);
}
