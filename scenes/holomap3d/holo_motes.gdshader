// ============================================================
// holo_motes.gdshader - Poussières de données holographiques (montée + boucle).
//
// Appliqué à un mesh de courts segments verticaux (PRIMITIVE_LINES). Chaque
// segment porte sa PHASE dans UV.x ; le vertex shader le fait dériver vers le
// haut selon TIME (boucle via fract) et fond aux extrémités → pluie de bits
// lumineux qui montent. Additif, sans écriture de profondeur.
//
// IMPORTANT : commentaires ASCII pur (parseur de shaders Godot).
// ============================================================
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;

uniform vec4  mote_color : source_color = vec4(0.40, 0.85, 1.00, 1.0);
uniform float vitesse = 0.06;   // vitesse de montée (lent)
uniform float hauteur = 3.5;    // hauteur de montée avant boucle

varying float v_a;

void vertex() {
	float t = fract(UV.x + TIME * vitesse);
	VERTEX.y += t * hauteur;
	// Fondu d'entrée (bas) et de sortie (haut) → la boucle est invisible.
	v_a = smoothstep(0.0, 0.12, t) * (1.0 - smoothstep(0.72, 1.0, t));
}

void fragment() {
	vec3 c = mote_color.rgb * 1.6;
	ALBEDO = c;
	EMISSION = c;
	ALPHA = COLOR.a * v_a;
}
