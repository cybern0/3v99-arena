// h1_vfx.gdshader  —  H1 (Boss Aigle Humanoïde, env rocheux/falaise)
// Thème : vent, air, plumes, bleu-blanc-doré
// anim_state: 0=idle  1=punch  2=run  3=kick  4=jump  5=react  6=die
shader_type spatial;
render_mode blend_add, depth_draw_never, cull_back, unshaded;

uniform float vfx_intensity : hint_range(0.0, 1.0) = 0.0;
uniform int   anim_state    : hint_range(0, 6)     = 0;

void fragment() {
	vec3  col = vec3(0.0);
	float a   = 0.0;

	if (anim_state == 0) {
		// idle — ondulation vent bleu-blanc sur tout le corps
		float wave = sin(TIME * 2.2 + UV.y * 6.0 + UV.x * 3.0) * 0.5 + 0.5;
		col = mix(vec3(0.3, 0.5, 1.0), vec3(0.9, 0.95, 1.0), wave) * 0.4;
		a   = wave * 0.25;

	} else if (anim_state == 1) {
		// punch — rafale blanche aveuglante
		col = vec3(0.95, 0.98, 1.0);
		a   = 0.95;

	} else if (anim_state == 2) {
		// run — traîne bleue-blanche directionnelle (haut du corps)
		float streak = clamp(UV.y - 0.3, 0.0, 1.0) * 1.5;
		col = vec3(0.4, 0.65, 1.0) * streak;
		a   = 0.5 * streak;

	} else if (anim_state == 3) {
		// kick — coupure d'air, ligne blanche horizontale
		float slash = abs(sin(TIME * 10.0 + UV.x * 8.0));
		col = vec3(1.0, 1.0, 0.9) * slash;
		a   = slash * 0.8;

	} else if (anim_state == 4) {
		// jump — shimmer doré + aspiration vers le haut
		float shine = fract(UV.y * 3.0 - TIME * 2.5);
		shine = smoothstep(0.8, 1.0, shine);
		col = vec3(1.0, 0.85, 0.3) * shine + vec3(0.2, 0.4, 0.9) * 0.3;
		a   = shine * 0.7 + 0.2;

	} else if (anim_state == 5) {
		// react — burst plumes blanches
		float burst = sin(TIME * 14.0) * 0.5 + 0.5;
		col = vec3(1.0, 1.0, 0.95) * burst;
		a   = burst * 0.9;
	}

	ALBEDO = col * vfx_intensity;
	ALPHA  = a   * vfx_intensity;
}
