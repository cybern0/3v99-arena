// w1_atmosphere.gdshader  —  W1 (Env rocheux / falaise / chaleur aride)
// Appliqué sur un grand PlaneMesh horizontal légèrement au-dessus du sol.
// Produit une distorsion de chaleur (mirage) + voile de poussière chaude.
// Le mesh doit avoir render_layer sur un layer dédié pour être derrière les persos.
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, unshaded;

uniform sampler2D SCREEN_TEXTURE : hint_screen_texture, filter_linear_mipmap;
uniform float distort_strength : hint_range(0.0, 0.015) = 0.006;
uniform float haze_opacity     : hint_range(0.0, 0.5)   = 0.18;
uniform vec4  haze_color       : source_color = vec4(0.92, 0.82, 0.60, 1.0);  // beige chaud

void fragment() {
	// Distorsion thermique simulée : ondulation horizontale lente
	float wave_x = sin(TIME * 1.8 + VERTEX.x * 0.8 + VERTEX.z * 0.5) * distort_strength;
	float wave_y = cos(TIME * 1.3 + VERTEX.z * 1.0) * distort_strength * 0.4;
	vec2 distorted = SCREEN_UV + vec2(wave_x, wave_y);

	vec3 screen = texture(SCREEN_TEXTURE, distorted).rgb;

	// Voile chaud (plus dense près des bords via UV)
	float edge_mask = smoothstep(0.15, 0.45, UV.x) * (1.0 - smoothstep(0.55, 0.85, UV.x));
	float veil      = haze_opacity * (1.0 - edge_mask * 0.6);

	ALBEDO = mix(screen, haze_color.rgb, veil);
	ALPHA  = clamp(veil + 0.1, 0.0, 0.55);
}
