// p1_vfx.gdshader  —  P1 (femme, nature)
// Additive overlay: simple & light.  No skin texture needed.
// anim_state: 0=idle  1=punch  2=run  3=kick  4=jump  5=react  6=die
shader_type spatial;
render_mode blend_add, depth_draw_never, cull_back, unshaded;

uniform float vfx_intensity : hint_range(0.0, 1.0) = 0.0;
uniform int   anim_state    : hint_range(0, 6)     = 0;

void fragment() {
	vec3  col = vec3(0.0);
	float a   = 0.0;

	if (anim_state == 0) {
		// idle — douce pulsation verte (respiration naturelle)
		float pulse = sin(TIME * 1.6) * 0.5 + 0.5;
		col = vec3(0.08, 0.55, 0.12) * pulse;
		a   = 0.18 * pulse;

	} else if (anim_state == 1 || anim_state == 3) {
		// punch / kick — éclair blanc-vert
		col = vec3(0.7, 1.0, 0.5);
		a   = 0.85;

	} else if (anim_state == 2) {
		// run — traîne verte en bas du mesh (UV.y ~ bas du perso)
		float trail = clamp(1.0 - UV.y * 1.5, 0.0, 1.0);
		col = vec3(0.1, 0.7, 0.15) * trail;
		a   = 0.35 * trail;

	} else if (anim_state == 4) {
		// jump — légère lueur bleu-vert
		col = vec3(0.15, 0.6, 0.5);
		a   = 0.4;

	} else if (anim_state == 5) {
		// react — flash rouge
		col = vec3(1.0, 0.05, 0.05);
		a   = 0.9;
	}
	// state 6 (die) — géré par shared_die.gdshader, rien ici

	ALBEDO = col * vfx_intensity;
	ALPHA  = a   * vfx_intensity;
}
