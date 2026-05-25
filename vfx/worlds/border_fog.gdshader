// border_fog.gdshader
// Appliqué sur un grand mesh plan/cylindre placé en bordure d'arène.
// UV.x = 0 (côté arène, transparent) → 1 (bordure, opaque)
// UV.y = 0 (bas) → 1 (haut), utilisé pour le fondu en hauteur.
//
// Usage dans le monde : 4 grands quads verticaux autour du terrain
// ou un CylinderMesh (flip normals) de rayon légèrement > terrain.
// Orienter de sorte que UV.x augmente vers l'extérieur.
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, unshaded;

uniform vec4  fog_color        : source_color = vec4(0.75, 0.70, 0.65, 1.0);
uniform float height_max       : hint_range(0.5, 30.0)  = 10.0;  // hauteur arête supérieure
uniform float height_fade_band : hint_range(0.1, 1.0)   = 0.25;  // bande de fondu haut
uniform float density          : hint_range(0.0, 1.0)   = 0.92;

void fragment() {
	// Fondu horizontal : pleinement opaque vers l'extérieur (UV.x → 1)
	float horiz = smoothstep(0.0, 0.6, UV.x);

	// Fondu vertical : disparaît doucement en haut pour éviter un mur plat
	float vert  = 1.0 - smoothstep(1.0 - height_fade_band, 1.0, UV.y);

	ALBEDO = fog_color.rgb;
	ALPHA  = horiz * vert * density * fog_color.a;
}
