// shared_die.gdshader
// Dissolve shader used by ALL characters on death.
// VFXController auto-copies albedo_texture + base_color from the original material.
// Assign a noise texture in the Inspector (any tiling noise works).
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_lambert, specular_disabled;

uniform sampler2D albedo_texture : source_color, hint_default_white;
uniform vec4      base_color     : source_color = vec4(0.75, 0.6, 0.45, 1.0);
uniform sampler2D noise_texture  : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform float     dissolve_amount : hint_range(0.0, 1.0) = 0.0;
// Edge glow color: tweak per character via VFXController if desired
uniform vec4      edge_color     : source_color = vec4(1.0, 0.45, 0.05, 1.0);

void fragment() {
	// Sample original albedo (fallback to base_color if no texture assigned)
	vec4 tex   = texture(albedo_texture, UV);
	vec4 color = mix(base_color, tex, step(0.02, length(tex.rgb)));

	// Noise-driven dissolve
	float noise = texture(noise_texture, UV * 1.8 + vec2(0.0, dissolve_amount * 0.4)).r;
	if (noise < dissolve_amount) { discard; }

	// Burning/glowing edge just before the dissolve clip
	float edge_w   = 0.06;
	float edge_fac = 1.0 - smoothstep(dissolve_amount, dissolve_amount + edge_w, noise);

	ALBEDO   = mix(color.rgb, edge_color.rgb, edge_fac);
	EMISSION = edge_color.rgb * edge_fac * 3.0;
	ALPHA    = 1.0;
}
