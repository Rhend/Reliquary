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
// Brume de profondeur : les aretes lointaines (par rapport a la camera)
// s'estompent → focus sur le centre, sensation de volume.
uniform float fog_debut = 16.0;
uniform float fog_fin = 30.0;
uniform float fog_min = 0.25;           // alpha/intensite residuels au loin

varying vec3 w_pos;

void vertex() {
	w_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float d = distance(w_pos, CAMERA_POSITION_WORLD);
	float fade = mix(1.0, fog_min, smoothstep(fog_debut, fog_fin, d));
	vec3 c = COLOR.rgb * emission_strength * fade;
	ALBEDO = c;
	EMISSION = c;
	ALPHA = COLOR.a * alpha_mult * fade;
}
