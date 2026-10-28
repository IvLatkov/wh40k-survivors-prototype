shader_type canvas_item;
render_mode unshaded;

uniform vec4 outline_color : source_color = vec4(0.85, 0.9, 1.0, 1.0);
uniform float outline_opacity : hint_range(0.0, 1.0) = 0.7;
instance uniform float magnet_strength = 1.0;
instance uniform float pulse_phase = 0.0;
varying vec4 item_tint;

void vertex() {
	item_tint = COLOR;
	// Pad the quad by two source pixels so wing tips never clip the outline.
	// Pulse an explicit base vertex, never the previous frame's transform.
	VERTEX = (VERTEX + sign(VERTEX) * 2.0) * (1.0 + 0.03 * sin(TIME * 6.2831853 / 1.6 + pulse_phase));
}

float inside_texture(vec2 uv) {
	vec2 inside = step(vec2(0.0), uv) * step(uv, vec2(1.0));
	return inside.x * inside.y;
}

void fragment() {
	vec2 pixel = TEXTURE_PIXEL_SIZE;
	vec2 uv = (UV - vec2(0.5)) * (vec2(1.0) + 4.0 * pixel) + vec2(0.5);
	vec4 skull = texture(TEXTURE, uv) * inside_texture(uv);
	float edge = 0.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			if (x != 0 || y != 0) {
				vec2 sample_uv = uv + vec2(float(x), float(y)) * pixel;
				edge = max(edge, texture(TEXTURE, sample_uv).a * inside_texture(sample_uv));
			}
		}
	}
	// A restrained dark outer keyline also separates pale skulls from ash/rock.
	float outer = edge;
	vec2 sample_uv = uv + vec2(2.0 * pixel.x, 0.0);
	outer = max(outer, texture(TEXTURE, sample_uv).a * inside_texture(sample_uv));
	sample_uv = uv - vec2(2.0 * pixel.x, 0.0);
	outer = max(outer, texture(TEXTURE, sample_uv).a * inside_texture(sample_uv));
	sample_uv = uv + vec2(0.0, 2.0 * pixel.y);
	outer = max(outer, texture(TEXTURE, sample_uv).a * inside_texture(sample_uv));
	sample_uv = uv - vec2(0.0, 2.0 * pixel.y);
	outer = max(outer, texture(TEXTURE, sample_uv).a * inside_texture(sample_uv));
	float colored_alpha = edge * min(1.0, outline_opacity * magnet_strength);
	float dark_alpha = outer * 0.35;
	float under_alpha = colored_alpha + dark_alpha * (1.0 - colored_alpha);
	vec3 under_rgb = (outline_color.rgb * colored_alpha + vec3(0.025, 0.03, 0.04) * dark_alpha * (1.0 - colored_alpha)) / max(under_alpha, 0.0001);
	float alpha = skull.a + under_alpha * (1.0 - skull.a);
	vec3 rgb = (skull.rgb * skull.a + under_rgb * under_alpha * (1.0 - skull.a)) / max(alpha, 0.0001);
	COLOR = vec4(rgb, alpha) * item_tint;
}
