// ============================================================
// holo_water.gdshader - Surface d'eau qui S'ECOULE (nappe cyan animee).
//
// Appliquee aux tuiles d'eau (PRIMITIVE_TRIANGLES) du gabarit. Le motif est
// calcule en coordonnees MONDE (w_pos.xz) -> continu d'une tuile a l'autre. Des
// bandes lumineuses (cretes de vague) defilent dans `flux_dir` et ondulent
// transversalement -> impression de courant. Additif HDR doux (sous le seuil de
// glow) + brume + reveal d'intro, coherents avec les autres shaders holo.
//
// IMPORTANT : commentaires ASCII pur (parseur de shaders Godot).
// ============================================================
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;

uniform vec4  eau_color : source_color = vec4(0.16, 0.42, 0.62, 1.0);
uniform float vitesse = 0.40;     // vitesse du courant
uniform float echelle = 3.0;      // densite des vagues
uniform float emission = 1.0;     // gain HDR global
uniform vec2  flux_dir = vec2(1.0, 0.35);  // direction du courant (monde XZ)
// Brume de profondeur + reveal d'intro (memes conventions que holo_line).
uniform float fog_debut = 22.0;
uniform float fog_fin = 46.0;
uniform float fog_min = 0.25;
uniform float reveal_r = 100000.0;

varying vec3 w_pos;

void vertex() {
	w_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	if (length(w_pos.xz) > reveal_r) {
		discard;
	}
	vec2 p = w_pos.xz;
	float t = TIME * vitesse;
	vec2 dir = normalize(flux_dir);
	vec2 perp = vec2(-dir.y, dir.x);
	float a = dot(p, dir);
	float b = dot(p, perp);
	// Bandes de courant qui defilent + ondulation transverse (serpentement).
	float wave  = sin(a * echelle - t * 2.0 + sin(b * echelle * 0.6 + t) * 1.2);
	float wave2 = sin(a * echelle * 1.7 - t * 3.1 + b * 0.5);
	float crest = smoothstep(0.4, 1.0, wave) * 0.7 + smoothstep(0.7, 1.0, wave2) * 0.4;
	float base = 0.32;
	vec3 col = eau_color.rgb * (base + crest) * emission;
	float d = distance(w_pos, CAMERA_POSITION_WORLD);
	float fade = mix(1.0, fog_min, smoothstep(fog_debut, fog_fin, d));
	col *= fade;
	ALBEDO = col;
	EMISSION = col;
	ALPHA = (0.25 + crest * 0.5) * fade;
}
