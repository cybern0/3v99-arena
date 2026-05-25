// w3_atmosphere.gdshader  —  W3 (Savane / Poussière / Chaleur sèche)
// Mur de poussière orangée + distorsion thermique marquée.
// Appliqué sur un PlaneMesh horizontal (sol) ET sur les plans de bordure.
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, unshaded;

uniform sampler2D SCREEN_TEXTURE : hint_screen_texture, filter_linear_mipmap;
uniform vec4  dust_color      : source_color = vec4(0.82, 0.62, 0.30, 1.0);  // brun-orange
uniform float dust_density    : hint_range(0.0, 1.0)   = 0.35;
uniform float distort_amount  : hint_range(0.0, 0.018) = 0.009;
uniform float scroll_speed    : hint_range(0.0, 2.0)   = 0.4;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.545);
}
float dust_noise(vec2 uv) {
	vec2 i = floor(uv); vec2 f = fract(uv);
	f = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x),
		mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x),
		f.y);
}

void fragment() {
	vec2 scroll = UV + vec2(TIME * scroll_speed * 0.06, 0.0);

	// Distorsion thermique sèche
	float dx = sin(TIME * 2.2 + VERTEX.x * 1.2) * distort_amount;
	float dy = cos(TIME * 1.7 + VERTEX.z * 0.9) * distort_amount * 0.3;
	vec3  screen = texture(SCREEN_TEXTURE, SCREEN_UV + vec2(dx, dy)).rgb;

	// Particules de poussière en couches
	float d1 = dust_noise(scroll * 4.0);
	float d2 = dust_noise(scroll * 8.0 + vec2(0.5, 0.2));
	float dust = d1 * 0.65 + d2 * 0.35;
	dust *= clamp(1.0 - UV.y * 2.0, 0.0, 1.0);   // plus dense au sol

	float alpha = dust * dust_density;
	ALBEDO = mix(screen, dust_color.rgb, clamp(alpha * 1.2, 0.0, 0.6));
	ALPHA  = clamp(alpha, 0.0, 0.65);
}
