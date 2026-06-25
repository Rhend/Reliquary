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
uniform float reveal_r = 100000.0;      // rayon de materialisation (intro)
// Focus : halo de quartier qui s'allume autour de la position survolee.
uniform vec2  focus_pos = vec2(0.0);
uniform float focus_force = 0.0;        // 0..1
uniform float focus_rayon = 2.2;

varying vec3 w_pos;

void vertex() {
	w_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float dxz = length(w_pos.xz);
	if (dxz > reveal_r) {
		discard;
	}
	float d = distance(w_pos, CAMERA_POSITION_WORLD);
	float fade = mix(1.0, fog_min, smoothstep(fog_debut, fog_fin, d));
	// Front lumineux de materialisation (anneau qui peint la carte).
	float front = smoothstep(reveal_r - 0.6, reveal_r, dxz);
	// Focus de quartier.
	float foc = focus_force * (1.0 - smoothstep(0.0, focus_rayon, distance(w_pos.xz, focus_pos)));
	float boost = 1.0 + 1.4 * foc + 2.5 * front;
	vec3 c = COLOR.rgb * emission_strength * fade * boost;
	ALBEDO = c;
	EMISSION = c;
	ALPHA = COLOR.a * alpha_mult * fade * (1.0 + 0.5 * foc + front);
}
