// w2_atmosphere.gdshader  —  W2 (Nature / Forêt / Météo tropicale humide)
// Brouillard de sol vert-gris + volutes de vapeur montantes.
// Appliqué sur 1 ou 2 PlaneMesh bas pour la brume de sol.
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, unshaded;

uniform vec4  mist_color   : source_color = vec4(0.72, 0.88, 0.70, 1.0);  // vert pâle
uniform float mist_density : hint_range(0.0, 1.0) = 0.55;
uniform float mist_speed   : hint_range(0.0, 2.0) = 0.25;

// Fonction de bruit simple pour les volutes
float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.545);
}
float mist_noise(vec2 uv) {
	vec2 i = floor(uv);
	vec2 f = fract(uv);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash(i);
	float b = hash(i + vec2(1.0, 0.0));
	float c = hash(i + vec2(0.0, 1.0));
	float d = hash(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

void fragment() {
	// Défilement lent de la brume
	vec2 scroll = UV + vec2(TIME * mist_speed * 0.04, TIME * mist_speed * 0.02);
	float n1 = mist_noise(scroll * 3.0);
	float n2 = mist_noise(scroll * 6.0 + vec2(0.3, 0.7));
	float mist = (n1 * 0.6 + n2 * 0.4);

	// Masque UV.y : concentre la brume en bas
	float height_mask = clamp(1.0 - UV.y * 2.5, 0.0, 1.0);

	float alpha = mist * height_mask * mist_density;

	ALBEDO = mist_color.rgb;
	ALPHA  = clamp(alpha, 0.0, 0.7);
}
