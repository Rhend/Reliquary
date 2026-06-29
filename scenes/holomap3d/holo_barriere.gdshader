// ============================================================
// holo_barriere.gdshader - Barriere d'energie verticale d'un lieu d'expedition.
//
// Applique a des PILIERS verticaux (croix de quads, PRIMITIVE_TRIANGLES) plantes a
// intervalle regulier le long du perimetre d'une zone. PILIERS D'ENERGIE VIVANTS :
// coeur de colonne lumineux, fines bandes qui remontent, une impulsion qui fait le
// TOUR de la zone (les piliers s'allument en vague), crepitement (flicker), liseré net
// en haut, base lumineuse. Additif, see-through. N'apparait qu'au survol via
// alpha_mult (0 = totalement invisible au repos).
//
// Encodage par sommet : UV.x = u le long de l'arete, UV.y = hauteur 0(base)->1(haut) ;
// COLOR = teinte de palier (rgb) + alpha de base. Commentaires ASCII pur (parseur).
// ============================================================
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;

uniform float emission_strength = 2.5;   // gain HDR MODERE : garde la TEINTE de tier (trop haut -> blanc)
uniform float alpha_mult = 0.0;          // 0 au repos -> invisible ; ->1 au survol
uniform float reveal_r = 100000.0;       // rayon de materialisation (intro)
uniform float fog_debut = 16.0;
uniform float fog_fin = 30.0;
uniform float fog_min = 0.25;
uniform float scan_speed = 1.3;          // vitesse des bandes montantes
uniform float flow_speed = 0.55;         // vitesse de l'impulsion qui fait le tour

varying vec3 w_pos;
varying vec3 w_center;
varying vec2 v_uv;

void vertex() {
	w_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	w_center = MODEL_MATRIX[3].xyz;          // centre du lieu (origine du noeud)
	v_uv = UV;
}

void fragment() {
	float dxz = length(w_pos.xz);
	if (dxz > reveal_r) { discard; }
	float d = distance(w_pos, CAMERA_POSITION_WORLD);
	float fade = mix(1.0, fog_min, smoothstep(fog_debut, fog_fin, d));

	float h = clamp(v_uv.y, 0.0, 1.0);                              // 0 base -> 1 haut
	float ang = atan(w_pos.z - w_center.z, w_pos.x - w_center.x);   // tour de la zone

	// Fines bandes d'energie qui remontent (le flux qui monte).
	float scan = 0.5 + 0.5 * sin(h * 22.0 - TIME * scan_speed * 6.28318);
	scan = pow(scan, 3.0);
	// Impulsion lumineuse qui circule autour du perimetre (un eclair qui fait le tour).
	float flow = 0.5 + 0.5 * sin(ang * 3.0 - TIME * flow_speed * 6.28318);
	flow = pow(flow, 3.0);
	// Crepitement : deux sinus desaccordes -> ca grouille, c'est vivant.
	float flick = 0.80 + 0.20 * sin(TIME * 26.0 + ang * 9.0) * sin(TIME * 13.0 + h * 7.0);

	// Profil vertical : dense en bas, s'estompe en montant ; liseres marques.
	float vgrad = pow(1.0 - h, 1.3);
	float top_edge = smoothstep(0.90, 1.0, h);     // liseré net au sommet
	float base_glow = smoothstep(0.30, 0.0, h);    // base lumineuse
	// Coeur de colonne : lumineux au centre du pilier, bords doux (effet faisceau).
	float core = pow(clamp(1.0 - abs(v_uv.x * 2.0 - 1.0), 0.0, 1.0), 1.5);

	float energy = (0.18 + 0.55 * scan + 0.7 * flow) * (0.30 + 0.85 * vgrad);
	energy = energy * flick + top_edge * 0.6 + base_glow * 0.45;
	energy *= (0.28 + 0.72 * core);                // colonne lumineuse, bords estompes

	vec3 c = COLOR.rgb * emission_strength * fade * energy;
	float a = COLOR.a * alpha_mult * fade * clamp(0.12 + energy * 0.95, 0.0, 1.0);
	ALBEDO = c;
	EMISSION = c;
	ALPHA = a;
}
