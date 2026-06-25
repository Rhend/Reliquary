// ============================================================
// holo_face.gdshader - Faces sombres semi-transparentes des bâtiments.
//
// Remplit les faces extérieures de la boîte d'un bâtiment en couleur très
// sombre + alpha réglable. ÉCRIT la profondeur (depth_draw_always) → les
// arêtes/lignes des bâtiments DERRIÈRE sont occultées (anti-fouillis), tout
// en laissant transparaître partiellement le fond. Les arêtes lumineuses
// (holo_line, additif) sont dessinées APRÈS et par-dessus (render_priority
// plus haut), donc restent nettes au-dessus de leurs faces.
//
// blend_mix (et non additif) : les faces ASSOMBRISSENT/masquent, elles
// n'ajoutent pas de lumière. IMPORTANT : commentaires ASCII pur.
// ============================================================
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_always, shadows_disabled;

uniform vec4  face_color : source_color = vec4(0.02, 0.03, 0.06, 1.0); // très sombre, légèrement teinté
uniform float opacite = 0.5;   // 0 = quasi transparent (holo) .. 1 = bien masquant

void fragment() {
	ALBEDO = face_color.rgb;
	ALPHA = clamp(opacite, 0.0, 1.0);
}
