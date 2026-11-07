shader_type canvas_item;

// Keep the supplied Bonobono image sharp, but replace its nearly uniform
// light-blue studio background with an intentionally loud rainbow.
void fragment() {
	vec4 photo = texture(TEXTURE, UV);
	vec3 background_blue = vec3(0.486, 0.733, 0.878);
	float blue_distance = distance(photo.rgb, background_blue);
	float background_mask = 1.0 - smoothstep(0.075, 0.18, blue_distance);
	vec3 rainbow = 0.55 + 0.45 * cos(
		6.283185 * (vec3(0.00, 0.33, 0.67) + UV.x * 1.15 - UV.y * 0.42)
	);
	COLOR = vec4(mix(photo.rgb, rainbow, background_mask), 1.0);
}
