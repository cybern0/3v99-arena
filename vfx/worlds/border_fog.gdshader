// half_sphere_dense_fog.gdshader (version continue sans arrêt à l'équateur)
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, unshaded;

uniform vec4 fog_color : source_color = vec4(0.75, 0.73, 0.70, 1.0);
uniform float density : hint_range(0.0, 101.0) = 100.0;           // Densité globale
uniform float center_density : hint_range(2.0, 11.0) = 10.0;    // Concentration au pôle
uniform float edge_width : hint_range(0.1, 2.0) = 1.35;         // Largeur du dégradé
uniform bool top_hemisphere = true; // true = pôle Nord dense, false = pôle Sud dense

void fragment() {
    // Distance depuis le pôle choisi (0 = pôle dense, 1 = pôle opposé)
    float dist_from_center = top_hemisphere ? UV.y : 1.0 - UV.y;
    
    // Profil de densité : très forte au pôle, décroît progressivement
    float density_shape = pow(1.0 - dist_from_center, center_density);
    
    // Dégradé transparent sur les bords (ne devient jamais 0 brusquement)
    float edge_alpha = 1.0 - pow(dist_from_center, edge_width);
    edge_alpha = smoothstep(0.0, 1.0, edge_alpha);
    
    // Alpha final – la transparence continue de diminuer au-delà de l'équateur
    float final_alpha = fog_color.a * density * density_shape * edge_alpha;
    
    ALBEDO = fog_color.rgb;
    ALPHA = final_alpha;
}