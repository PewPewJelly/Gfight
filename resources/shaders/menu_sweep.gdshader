shader_type canvas_item;
// Main menu: a slanted band that sweeps across a menu word. It recolors only the glyph
// pixels, so nothing shows outside the letters.

uniform vec4 band_color : source_color = vec4(0.92, 0.66, 0.14, 1.0);
// Band centre along the sweep axis, in word coordinates. Far negative = no band.
uniform float band_pos = -100000.0;
uniform float band_half_width = 22.0;
// x shift per unit of y; positive leans the band like "\".
uniform float slant = 0.6;
// This label's x inside the word, so Body and Last share one band.
uniform float offset_x = 0.0;
// Keep the part the band has already passed in band_color (the last letter).
uniform bool keep_passed = false;

varying vec2 local_pos;

void vertex() {
	local_pos = VERTEX;
}

void fragment() {
	vec4 color = texture(TEXTURE, UV) * COLOR;
	float along = local_pos.x + offset_x - local_pos.y * slant;
	if (abs(along - band_pos) <= band_half_width || (keep_passed && along < band_pos)) {
		color.rgb = band_color.rgb;
	}
	COLOR = color;
}
