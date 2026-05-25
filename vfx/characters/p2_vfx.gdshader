// p2_vfx.gdshader  —  P2 (garçon, village)
// Overlay minimaliste — P2 est le plus simple de tous.
// anim_state: 0=idle  1=punch  2=run  3=kick  4=jump  5=react  6=die
shader_type spatial;
render_mode blend_add, depth_draw_never, cull_back, unshaded;

uniform float vfx_intensity : hint_range(0.0, 1.0) = 0.0;
uniform int   anim_state    : hint_range(0, 6)     = 0;

void fragment() {
	vec3  col = vec3(0.0);
	float a   = 0.0;

	// idle (0) — aucun effet, personnage ordinaire du village
	if (anim_state == 1 || anim_state == 3) {
		// punch / kick — flash jaune-orange léger
		col = vec3(1.0, 0.75, 0.1);
		a   = 0.7;

	} else if (anim_state == 5) {
		// react — flash rouge
		col = vec3(1.0, 0.05, 0.05);
		a   = 0.85;
	}
	// run (2), jump (4), die (6) — pas d'overlay

	ALBEDO = col * vfx_intensity;
	ALPHA  = a   * vfx_intensity;
}
