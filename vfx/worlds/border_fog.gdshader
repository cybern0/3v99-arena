shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, unshaded;

uniform vec4  fog_color   : source_color         = vec4(0.75, 0.73, 0.70, 1.0);
uniform float opaque_end  : hint_range(0.0, 1.0) = 0.3;  // était 0.35 → juste le bord
uniform float fade_end    : hint_range(0.0, 1.0) = 0.4;  // était 0.65 → fondu court
uniform bool  top_hemisphere                      = true;

void fragment() {
    float d = top_hemisphere ? UV.y : (1.0 - UV.y);
    float alpha;
    if (d < opaque_end) {
        alpha = 1.0;
    } else {
        alpha = 1.0 - smoothstep(opaque_end, fade_end, d);
    }
    ALBEDO = fog_color.rgb;
    ALPHA  = alpha * fog_color.a;
}
