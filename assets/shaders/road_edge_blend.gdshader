shader_type canvas_item;

// Offline exterior-distance alpha fields, 5x3 tiles. One additional lookup;
// no RGB changes, blur, time, screen reads, noise or per-frame parameters.
uniform sampler2D edge_masks : filter_nearest, repeat_disable;
instance uniform float edge_index = 0.0;

void fragment() {
	vec2 tile = vec2(mod(edge_index, 5.0), floor(edge_index / 5.0));
	vec2 mask_uv = (UV + tile) / vec2(5.0, 3.0);
	COLOR.a *= texture(edge_masks, mask_uv).r;
}
