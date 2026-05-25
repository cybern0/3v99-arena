// h2_vfx.gdshader  —  H2 (Boss Caméléon Humanoïde, nature/forêt)
// Thème : camouflage, couleurs changeantes, distorsion, vert-brun-écailles
// anim_state: 0=idle  1=punch  2=run  3=kick  4=jump  5=react  6=die
shader_type spatial;
render_mode blend_add, depth_draw_never, cull_back, unshaded;

uniform float vfx_intensity : hint_range(0.0, 1.0) = 0.0;
uniform int   anim_state    : hint_range(0, 6)     = 0;

// Utilitaire : palette de couleurs caméléon basée sur sin/cos
vec3 chameleon_color(float t) {
	return vec3(
		sin(t * 1.1) * 0.5 + 0.5,
		sin(t * 0.7 + 2.0) * 0.5 + 0.5,
		sin(t * 0.4 + 4.0) * 0.2 + 0.1
	);
}

void fragment() {
	vec3  col = vec3(0.0);
	float a   = 0.0;

	if (anim_state == 0) {
		// idle — cycle lent vert↔brun (camouflage passif)
		float t   = TIME * 0.5 + UV.x * 2.0 + UV.y * 1.5;
		col = chameleon_color(t) * 0.35;
		a   = 0.2;

	} else if (anim_state == 1) {
		// punch — flash vert acide (frappe de la langue)
		col = vec3(0.2, 1.0, 0.1);
		a   = 0.9;

	} else if (anim_state == 2) {
		// run — shimmer de camouflage (légère transparence ondulante)
		float shimmer = sin(TIME * 5.0 + UV.y * 10.0) * 0.5 + 0.5;
		col = chameleon_color(TIME * 0.3) * shimmer * 0.4;
		a   = shimmer * 0.3;

	} else if (anim_state == 3) {
		// kick — distorsion UV  → simulée par un pattern rayé rapide
		float dist = sin(UV.x * 20.0 + TIME * 8.0) * 0.5 + 0.5;
		col = mix(vec3(0.1, 0.5, 0.05), vec3(0.6, 0.9, 0.2), dist);
		a   = dist * 0.75;

	} else if (anim_state == 4) {
		// jump — explosion de couleurs (toutes les teintes caméléon)
		float t = TIME * 2.0 + UV.x * 4.0 + UV.y * 4.0;
		col = chameleon_color(t);
		a   = 0.8;

	} else if (anim_state == 5) {
		// react — flash clair aveuglant (perte de contrôle chromatique)
		float flash = abs(sin(TIME * 15.0));
		col = vec3(1.0, 1.0, 0.5) * flash;
		a   = flash * 0.95;
	}

	ALBEDO = col * vfx_intensity;
	ALPHA  = a   * vfx_intensity;
}
