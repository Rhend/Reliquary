// ============================================================
// holo_line.gdshader - Materiau d'arete holographique 3D (wireframe emissif).
//
// Applique aux MeshInstance3D en PRIMITIVE_LINES (ville, reliefs, grille,
// circuits, pins, anneaux). Couleur portee par les vertex colors (cyan base
// ou magenta accent) ; emission HDR -> declenche le glow du WorldEnvironment.
// Rendu additif sans ecriture de profondeur = aspect hologramme see-through.
//
// `emission_strength` et `alpha_mult` sont animes par instance (les marqueurs
// dupliquent ce materiau pour pulser). IMPORTANT : commentaires ASCII pur.
// ============================================================
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;

uniform float emission_strength = 2.0;  // gain HDR (>1 -> glow)
uniform float alpha_mult = 1.0;         // opacite globale (pulse / survol)

void fragment() {
	vec3 c = COLOR.rgb * emission_strength;
	ALBEDO = c;
	EMISSION = c;
	ALPHA = COLOR.a * alpha_mult;
}
