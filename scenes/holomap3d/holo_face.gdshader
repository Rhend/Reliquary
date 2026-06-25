// ============================================================
// holo_face.gdshader - Faces sombres semi-transparentes + fenetres allumees.
//
// Remplit les faces exterieures des batiments en couleur tres sombre + alpha
// reglable, ECRIT la profondeur (occlusion anti-fouillis). Ajoute des FENETRES
// allumees (grille emissive sur les facades, scintillement doux) -> ville
// habitee. Supporte le REVEAL radial d'intro (discard au-dela de reveal_r).
//
// IMPORTANT : commentaires ASCII pur (parseur de shaders Godot).
// ============================================================
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_always, shadows_disabled;

uniform vec4  face_color : source_color = vec4(0.02, 0.03, 0.06, 1.0);
uniform float opacite = 0.5;
uniform float reveal_r = 100000.0;   // rayon de materialisation (intro)
uniform vec4  fenetre_color : source_color = vec4(0.95, 0.85, 0.55, 1.0); // ambre chaud
uniform float fenetre_densite = 0.16; // proportion de fenetres allumees
uniform float fenetre_taille = 0.16;  // taille d'une fenetre (unites monde)

varying vec3 w_pos;
varying vec3 w_nrm;

float h21(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void vertex() {
	w_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	w_nrm = (MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz;
}

void fragment() {
	if (length(w_pos.xz) > reveal_r) {
		discard;
	}
	// Fenetres : grille sur les 2 axes tangents a la face (selon la normale).
	vec3 an = abs(w_nrm);
	vec2 uvw;
	if (an.x >= an.z && an.x >= an.y) {
		uvw = vec2(w_pos.z, w_pos.y);
	} else if (an.z >= an.x && an.z >= an.y) {
		uvw = vec2(w_pos.x, w_pos.y);
	} else {
		uvw = vec2(w_pos.x, w_pos.z); // toit
	}
	vec2 g = uvw / fenetre_taille;
	vec2 cell = floor(g);
	vec2 f = fract(g);
	float lit = step(1.0 - fenetre_densite, h21(cell));
	float win = step(0.25, f.x) * step(f.x, 0.78) * step(0.3, f.y) * step(f.y, 0.82);
	float tw = 0.55 + 0.45 * sin(TIME * 1.3 + h21(cell) * 53.0);
	float w = lit * win * tw;

	ALBEDO = face_color.rgb;
	EMISSION = fenetre_color.rgb * w * 1.4;
	ALPHA = clamp(opacite + w * 0.5, 0.0, 1.0);  // fenetres allumees plus opaques
}
