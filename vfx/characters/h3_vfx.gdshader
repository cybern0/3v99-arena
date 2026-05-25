// h3_vfx.gdshader  —  H3 (Boss Zébu Méka Humanoïde, savane/poussière)
// Thème : métal, vapeur, orange-rouge, scan lines, chaleur mécanique
// anim_state: 0=idle  1=punch  2=run  3=kick  4=jump  5=react  6=die
shader_type spatial;
render_mode blend_add, depth_draw_never, cull_back, unshaded;

uniform float vfx_intensity : hint_range(0.0, 1.0) = 0.0;
uniform int   anim_state    : hint_range(0, 6)     = 0;

void fragment() {
	vec3  col = vec3(0.0);
	float a   = 0.0;

	if (anim_state == 0) {
		// idle — pulsation rouge-orange sur la partie basse (UV.y = 0 en bas)
		float pulse = sin(TIME * 1.8) * 0.5 + 0.5;
		float zone  = clamp(1.0 - UV.y * 2.0, 0.0, 1.0);   // bas du corps
		col = vec3(1.0, 0.3, 0.02) * zone * pulse;
		a   = zone * pulse * 0.4;

	} else if (anim_state == 1) {
		// punch — onde de choc orange-blanche
		float shockwave = abs(sin(TIME * 12.0 + UV.x * 5.0));
		col = mix(vec3(1.0, 0.5, 0.1), vec3(1.0, 1.0, 0.8), shockwave);
		a   = shockwave * 0.9;

	} else if (anim_state == 2) {
		// run — scan lines mécaniques + shimmer métallique
		float scan  = step(0.5, fract(UV.y * 8.0 - TIME * 3.0));
		float metal = fract(UV.x * 4.0 + TIME * 0.5) * 0.3 + 0.1;
		col = vec3(0.8, 0.6, 0.2) * scan + vec3(0.5, 0.4, 0.3) * metal;
		a   = scan * 0.45 + metal * 0.2;

	} else if (anim_state == 3) {
		// kick — explosion de poussière sépia
		float dust = sin(TIME * 6.0 + UV.y * 8.0 + UV.x * 5.0) * 0.5 + 0.5;
		col = vec3(0.75, 0.5, 0.25) * dust;
		a   = dust * 0.7;

	} else if (anim_state == 4) {
		// jump — lueur de propulsion, orange chaud depuis le bas
		float thrust = clamp(1.0 - UV.y * 1.8, 0.0, 1.0);
		float pulse  = sin(TIME * 8.0) * 0.3 + 0.7;
		col = vec3(1.0, 0.45, 0.05) * thrust * pulse;
		a   = thrust * pulse * 0.8;

	} else if (anim_state == 5) {
		// react — étincelles jaune-blanc (surtension électromécanique)
		float spark = step(0.7, fract(sin(dot(UV + TIME * 0.3, vec2(12.9898, 78.233))) * 43758.545));
		col = mix(vec3(1.0, 0.9, 0.2), vec3(1.0, 1.0, 1.0), spark);
		a   = spark * 0.95 + 0.1;
	}

	ALBEDO = col * vfx_intensity;
	ALPHA  = a   * vfx_intensity;
}
